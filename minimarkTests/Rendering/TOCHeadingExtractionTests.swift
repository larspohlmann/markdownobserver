//
//  TOCHeadingExtractionTests.swift
//  minimarkTests
//
//  Regression test for #404.
//
//  When a file changes on disk, `DocumentPresenter` clears the Swift-side TOC
//  and pushes the new markdown into the already-loaded page via
//  `__minimarkUpdateRenderedMarkdown`. The runtime must post the headings after
//  every render, even when they did not change. Otherwise the Swift heading
//  list stays empty and the TOC button disappears.
//

import Testing
import Foundation
import WebKit
@testable import minimark

@MainActor
@Suite
struct TOCHeadingExtractionTests {

    // MARK: - Helpers

    private final class MessageRecorder: NSObject, WKScriptMessageHandler {
        var received: [[TOCHeading]] = []

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == MarkdownWebView.tocMessageName else { return }
            let payload = (message.body as? [[String: Any]]) ?? []
            received.append(TOCHeading.fromJavaScriptPayload(payload))
        }
    }

    private final class LoadObserver: NSObject, WKNavigationDelegate {
        nonisolated(unsafe) static var key: UInt8 = 0
        let continuation: CheckedContinuation<Void, Never>
        var fired = false

        init(continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !fired else { return }
            fired = true
            continuation.resume()
        }
    }

    private func makeWebView(recorder: MessageRecorder) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: MarkdownWebView.tocMessageName)
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
    }

    private func loadRenderedDocument(markdown: String, in webView: WKWebView) async throws {
        let rendered = try MarkdownRenderingService().render(
            markdown: markdown,
            changedRegions: [],
            unsavedChangedRegions: [],
            theme: ThemeKind.blackOnWhite.themeDefinition,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let observer = LoadObserver(continuation: continuation)
            webView.navigationDelegate = observer
            objc_setAssociatedObject(webView, &LoadObserver.key, observer, .OBJC_ASSOCIATION_RETAIN)
            webView.loadHTMLString(rendered.htmlDocument, baseURL: Bundle.main.bundleURL)
        }
    }

    /// Pushes new markdown into the loaded page the same way
    /// `MarkdownWebView.Coordinator.applyInPlaceContentUpdateIfPossible` does.
    private func updateRenderedMarkdownInPlace(_ markdown: String, in webView: WKWebView) async throws {
        let payloadBase64 = try JSONBase64MarkdownRuntimePayloadEncoder().makePayloadBase64(
            markdown: markdown,
            changedRegions: [],
            unsavedChangedRegions: []
        )
        let result = try await webView.evaluateJavaScript(
            "window.__minimarkUpdateRenderedMarkdown('\(payloadBase64)', null)"
        )
        #expect((result as? Bool) == true)
    }

    private func waitForMessages(
        _ recorder: MessageRecorder,
        count: Int,
        timeout: Duration = .seconds(3)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while recorder.received.count < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Tests

    @Test
    func inPlaceUpdateWithUnchangedHeadingsStillPostsHeadings() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)

        try await loadRenderedDocument(
            markdown: "# Title\n\nFirst body.\n\n## Section\n\nMore text.",
            in: webView
        )
        try await waitForMessages(recorder, count: 1)
        try #require(recorder.received.count == 1)

        try await updateRenderedMarkdownInPlace(
            "# Title\n\nEdited body.\n\n## Section\n\nMore text.",
            in: webView
        )
        try await waitForMessages(recorder, count: 2)

        #expect(recorder.received.count == 2)
        #expect(recorder.received.last?.map(\.title) == ["Title", "Section"])
    }
}
