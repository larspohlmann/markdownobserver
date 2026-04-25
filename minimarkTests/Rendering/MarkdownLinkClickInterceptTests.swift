//
//  MarkdownLinkClickInterceptTests.swift
//  minimarkTests
//
//  Regression test for the JS click interceptor.
//
//  WKWebView silently drops left-click navigation on `file://` URLs when the
//  document was loaded via `loadHTMLString(html, baseURL: bundleURL)`. The
//  navigation delegate's `decidePolicyForNavigationAction` is never called for
//  those clicks. The fix routes markdown-link clicks through a JS user script
//  that preventDefaults and posts the URL to a `WKScriptMessageHandler`. This
//  test exercises that exact path against a real WKWebView so future
//  regressions are caught.
//

import Testing
import Foundation
import WebKit
@testable import minimark

@MainActor
@Suite
struct MarkdownLinkClickInterceptTests {

    // MARK: - Helpers

    private static let bundleBaseURL = URL(fileURLWithPath: "/Applications/MarkdownObserver.app/")

    private final class MessageRecorder: NSObject, WKScriptMessageHandler {
        var continuation: CheckedContinuation<[String: Any], Never>?

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == MarkdownWebView.linkClickMessageName else { return }
            let payload = (message.body as? [String: Any]) ?? [:]
            continuation?.resume(returning: payload)
            continuation = nil
        }
    }

    private func makeWebView(recorder: MessageRecorder) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: MarkdownWebView.markdownLinkInterceptScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(recorder, name: MarkdownWebView.linkClickMessageName)
        return WKWebView(frame: .zero, configuration: configuration)
    }

    /// Loads HTML containing the given anchor markup and waits for the page
    /// to finish loading.
    private func loadDocument(in webView: WKWebView, anchor: String) async {
        let html = """
        <!DOCTYPE html>
        <html><body>
            \(anchor)
        </body></html>
        """

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let observer = LoadObserver(continuation: continuation)
            webView.navigationDelegate = observer
            // Hold the observer alive for the duration of the load.
            objc_setAssociatedObject(webView, &LoadObserver.key, observer, .OBJC_ASSOCIATION_RETAIN)
            webView.loadHTMLString(html, baseURL: Self.bundleBaseURL)
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

    /// Synthesizes a left-click on the anchor element by ID.
    private func clickAnchor(id: String, in webView: WKWebView) async throws {
        let script = """
        (function() {
            var el = document.getElementById(\(jsString(id)));
            if (!el) return false;
            var ev = new MouseEvent('click', {
                bubbles: true,
                cancelable: true,
                button: 0
            });
            el.dispatchEvent(ev);
            return true;
        })();
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    private func jsString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        // Strip the surrounding [] so we get a JSON-encoded string literal.
        let stripped = String(json.dropFirst().dropLast())
        return stripped
    }

    private func awaitNextMessage(_ recorder: MessageRecorder) async -> [String: Any] {
        await withCheckedContinuation { continuation in
            recorder.continuation = continuation
        }
    }

    // MARK: - Tests

    @Test
    func clickOnRelativeMarkdownLinkPostsResolvedURL() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)
        await loadDocument(
            in: webView,
            anchor: #"<a id="link" href="feedback_xyz.md">notes</a>"#
        )

        async let payload = awaitNextMessage(recorder)
        try await clickAnchor(id: "link", in: webView)
        let body = await payload

        // The URL posted is the WKWebView-resolved absolute href, which is the
        // bundle base URL joined with the relative href.
        let urlString = try #require(body["url"] as? String)
        let url = try #require(URL(string: urlString))
        #expect(url.isFileURL)
        #expect(url.path == "/Applications/MarkdownObserver.app/feedback_xyz.md")
    }

    @Test
    func clickOnMarkdownExtensionLinkAlsoPosts() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)
        await loadDocument(
            in: webView,
            anchor: #"<a id="link" href="long.markdown">long</a>"#
        )

        async let payload = awaitNextMessage(recorder)
        try await clickAnchor(id: "link", in: webView)
        let body = await payload

        let urlString = try #require(body["url"] as? String)
        #expect(urlString.hasSuffix("/long.markdown"))
    }

    @Test
    func clickOnNonMarkdownLinkDoesNotPost() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)
        await loadDocument(
            in: webView,
            anchor: #"<a id="link" href="image.png">img</a>"#
        )

        try await clickAnchor(id: "link", in: webView)

        // Give the JS a moment to run; if it were going to post, it would have.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.continuation == nil, "no message should have been posted")
    }

    @Test
    func clickOnExternalHttpsLinkDoesNotPost() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)
        await loadDocument(
            in: webView,
            anchor: #"<a id="link" href="https://example.com">ext</a>"#
        )

        try await clickAnchor(id: "link", in: webView)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.continuation == nil)
    }

    @Test
    func clickOnFragmentLinkDoesNotPost() async throws {
        let recorder = MessageRecorder()
        let webView = makeWebView(recorder: recorder)
        await loadDocument(
            in: webView,
            anchor: ##"<a id="link" href="#section">anchor</a>"##
        )

        try await clickAnchor(id: "link", in: webView)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(recorder.continuation == nil)
    }
}
