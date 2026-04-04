import SwiftUI
import WebKit
import AppKit
import OSLog

struct MarkdownWebView: NSViewRepresentable {
    private static let scrollSyncMessageName = "minimarkScrollSync"
    private static let sourceEditMessageName = "minimarkSourceEdit"
    private static let sourceEditorDiagnosticMessageName = "minimarkSourceEditorDiagnostic"
    private static let scrollSyncObserverScript = ReaderJavaScriptLoader.scrollSyncObserverJavaScript

    let htmlDocument: String
    let documentIdentity: String?
    var accessibilityIdentifier: String = "reader-preview"
    var accessibilityValue: String = "file=none|regions=0"
    var reloadToken: Int = 0
    var diagnosticName: String = "reader-web"
    var postLoadStatusScript: String?
    var changedRegionNavigationRequest: ChangedRegionNavigationRequest?
        var scrollSyncRequest: ScrollSyncRequest?
    var supportsInPlaceContentUpdates: Bool = false
    var reloadAnchorProgress: Double?
    var onFatalCrash: () -> Void = {}
    var onPostLoadStatus: (String?) -> Void = { _ in }
        var onScrollSyncObservation: (ScrollSyncObservation) -> Void = { _ in }
    var onSourceEdit: (String) -> Void = { _ in }
    var onDroppedFileURLs: ([URL]) -> Void = { _ in }
        var onDropTargetedChange: (DropTargetingUpdate) -> Void = { _ in }
        var canAcceptDroppedFileURLs: ([URL]) -> Bool = { _ in true }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MarkdownWebContainerView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.scrollSyncObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: Self.scrollSyncMessageName)
        configuration.userContentController.add(context.coordinator, name: Self.sourceEditMessageName)
        configuration.userContentController.add(context.coordinator, name: Self.sourceEditorDiagnosticMessageName)

        let webView = DropAwareWKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        webView.isInspectable = true
        #endif
        let containerView = MarkdownWebContainerView(webView: webView)
        context.coordinator.attach(webView, containerView: containerView)
        context.coordinator.onDroppedFileURLs = onDroppedFileURLs
        context.coordinator.onDropTargetedChange = onDropTargetedChange
        context.coordinator.canAcceptDroppedFileURLs = canAcceptDroppedFileURLs
        webView.dropDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = true
        webView.setAccessibilityIdentifier(accessibilityIdentifier)
        webView.setAccessibilityLabel("Rendered markdown content")
        webView.setAccessibilityValue(accessibilityValue)
        return containerView
    }

    func updateNSView(_ containerView: MarkdownWebContainerView, context: Context) {
        let webView = containerView.webView
        context.coordinator.diagnosticName = diagnosticName
        context.coordinator.postLoadStatusScript = postLoadStatusScript
        context.coordinator.onFatalCrash = onFatalCrash
        context.coordinator.onPostLoadStatus = onPostLoadStatus
        context.coordinator.onScrollSyncObservation = onScrollSyncObservation
        context.coordinator.onSourceEdit = onSourceEdit
        context.coordinator.onDroppedFileURLs = onDroppedFileURLs
        context.coordinator.onDropTargetedChange = onDropTargetedChange
        context.coordinator.canAcceptDroppedFileURLs = canAcceptDroppedFileURLs
        context.coordinator.reloadAnchorProgress = reloadAnchorProgress
        context.coordinator.supportsInPlaceContentUpdates = supportsInPlaceContentUpdates
        context.coordinator.handleChangedRegionNavigationIfNeeded(changedRegionNavigationRequest, in: webView)
        context.coordinator.handleScrollSyncRequestIfNeeded(scrollSyncRequest, in: webView)
        webView.setAccessibilityIdentifier(accessibilityIdentifier)
        webView.setAccessibilityValue(accessibilityValue)
        context.coordinator.prepareForRetryIfNeeded(reloadToken, in: webView)

        let documentChanged = context.coordinator.prepareForDocumentChangeIfNeeded(documentIdentity)
        guard documentChanged || context.coordinator.lastHTMLDocument != htmlDocument else {
            return
        }

        if !documentChanged,
           context.coordinator.applyInPlaceContentUpdateIfPossible(htmlDocument, in: webView) {
            context.coordinator.lastHTMLDocument = htmlDocument
            return
        }

        context.coordinator.lastHTMLDocument = htmlDocument
        context.coordinator.loadHTMLDocument(htmlDocument, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, DropAwareWKWebViewDelegate, WKScriptMessageHandler {
        private static let verboseDiagnosticsEnabled = {
            let environment = ProcessInfo.processInfo.environment
            return environment["MINIMARK_VERBOSE_WEB_LOGS"] == "1"
        }()

        private enum LinkAction {
            case allow
            case cancel
            case openExternal(URL)
            case scrollToFragment(String)
        }

        private weak var webView: WKWebView?
        private weak var containerView: MarkdownWebContainerView?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "minimark", category: "MarkdownWebView")
        let crashRecovery = WebViewCrashRecoveryHandler()
        let scrollSync = WebViewScrollSyncController()
        var lastHTMLDocument: String?
        var diagnosticName: String = "reader-web"
        var postLoadStatusScript: String?
        private var lastDocumentIdentity: String?
        private var hasCompletedFirstLoad = false
        private var latestReloadRequestID = 0
        private var lastReloadToken: Int?
        private var lastChangedRegionNavigationRequestID: Int?
        private var pendingChangedRegionNavigationRequest: ChangedRegionNavigationRequest?
        var onFatalCrash: () -> Void = {}
        var onPostLoadStatus: (String?) -> Void = { _ in }
        var onScrollSyncObservation: (ScrollSyncObservation) -> Void = { _ in }
        var onSourceEdit: (String) -> Void = { _ in }
        var onDroppedFileURLs: ([URL]) -> Void = { _ in }
        var onDropTargetedChange: (DropTargetingUpdate) -> Void = { _ in }
        var canAcceptDroppedFileURLs: ([URL]) -> Bool = { _ in true }
        var supportsInPlaceContentUpdates = false
        var reloadAnchorProgress: Double?

        func attach(_ webView: WKWebView, containerView: MarkdownWebContainerView) {
            self.webView = webView
            self.containerView = containerView
            scrollSync.containerView = containerView
            scrollSync.logger = logger
        }

        func prepareForDocumentChangeIfNeeded(_ identity: String?) -> Bool {
            guard identity != lastDocumentIdentity else {
                return false
            }

            lastDocumentIdentity = identity
            hasCompletedFirstLoad = false
            crashRecovery.resetState()
            scrollSync.cancelPendingRestore()
            pendingChangedRegionNavigationRequest = nil
            scrollSync.resetForDocumentChange()
            logDebug("document change detected")
            return true
        }

        func prepareForRetryIfNeeded(_ reloadToken: Int, in webView: WKWebView) {
            guard lastReloadToken != reloadToken else {
                return
            }

            lastReloadToken = reloadToken
            crashRecovery.unlock()
            hasCompletedFirstLoad = false
            scrollSync.cancelPendingRestore()
            pendingChangedRegionNavigationRequest = nil
            scrollSync.resetForDocumentChange()
            logInfo("reload requested by retry token")

            if let lastHTMLDocument {
                loadHTMLDocument(lastHTMLDocument, in: webView)
            }
        }

        func loadHTMLDocument(_ htmlDocument: String, in webView: WKWebView) {
            guard !crashRecovery.isCrashRecoveryLocked else {
                logInfo("load skipped because crash recovery is locked")
                return
            }

            latestReloadRequestID += 1
            let requestID = latestReloadRequestID
            scrollSync.cancelPendingRestore()
            logDebug("loading HTML document")

            guard hasCompletedFirstLoad else {
                scrollSync.cancelPendingRestore()
                webView.loadHTMLString(htmlDocument, baseURL: Bundle.main.bundleURL)
                return
            }

            scrollSync.captureScrollSnapshot(in: webView) { [weak self, weak webView] snapshot in
                guard
                    let self,
                    let webView,
                    self.latestReloadRequestID == requestID
                else {
                    return
                }

                self.scrollSync.prepareForReloadRestore(
                    snapshot: snapshot,
                    fallbackSnapshot: self.scrollSync.lastObservedScrollSnapshot,
                    reloadAnchorProgress: self.reloadAnchorProgress
                )
                self.captureVisibleSnapshot(in: webView) { [weak self, weak webView] image in
                    guard
                        let self,
                        let webView,
                        self.latestReloadRequestID == requestID
                    else {
                        return
                    }

                    if self.scrollSync.isRestoringReloadScroll,
                       let image,
                       let containerView = self.containerView {
                        containerView.showReloadSnapshotOverlay(image)
                    } else {
                        self.containerView?.hideReloadSnapshotOverlay()
                    }

                    webView.loadHTMLString(htmlDocument, baseURL: Bundle.main.bundleURL)
                }
            }
        }

        func applyInPlaceContentUpdateIfPossible(_ htmlDocument: String, in webView: WKWebView) -> Bool {
            guard supportsInPlaceContentUpdates,
                  hasCompletedFirstLoad,
                                    let payloadBase64 = extractRuntimePayloadBase64(from: htmlDocument),
                                    let cssBase64 = extractRuntimeCSSBase64(from: htmlDocument) else {
                return false
            }

            let themeJSBase64 = extractRuntimeThemeJSBase64(from: htmlDocument)

            let anchorProgressLiteral: String
            if let reloadAnchorProgress {
                anchorProgressLiteral = String(min(max(reloadAnchorProgress, 0), 1))
            } else {
                anchorProgressLiteral = "null"
            }

            let themeJSLiteral: String
            if let themeJSBase64 {
                themeJSLiteral = javaScriptStringLiteral(themeJSBase64)
            } else {
                themeJSLiteral = "null"
            }

            scrollSync.setRestoringReloadScroll(reloadAnchorProgress != nil)
            let script = """
            (() => {
                            if (typeof window.__minimarkApplyRuntimeCSS === 'function') {
                                window.__minimarkApplyRuntimeCSS(
                                    \(javaScriptStringLiteral(cssBase64))
                                );
                            }
              var themeJSBase64 = \(themeJSLiteral);
              var previousThemeJSBase64 = Object.prototype.hasOwnProperty.call(window, '__minimarkLastThemeJSBase64')
                ? window.__minimarkLastThemeJSBase64
                : null;
              var shouldRefreshThemeJS = previousThemeJSBase64 !== themeJSBase64;
              if (shouldRefreshThemeJS && typeof window.__minimarkThemeCleanup === 'function') {
                window.__minimarkThemeCleanup();
                delete window.__minimarkThemeCleanup;
              }
              if (shouldRefreshThemeJS) {
                if (themeJSBase64) {
                  try {
                    var binary = atob(themeJSBase64);
                    var bytes = Uint8Array.from(binary, function(c) { return c.charCodeAt(0); });
                    var themeJS = new TextDecoder().decode(bytes);
                    new Function(themeJS)();
                  } catch(e) { console.error('Theme JS error:', e); }
                }
                window.__minimarkLastThemeJSBase64 = themeJSBase64;
              }
              if (typeof window.__minimarkUpdateRenderedMarkdown !== 'function') {
                return false;
              }
              return window.__minimarkUpdateRenderedMarkdown(\(javaScriptStringLiteral(payloadBase64)), \(anchorProgressLiteral));
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self else {
                    return
                }

                let didUpdate = (result as? Bool) == true
                if !didUpdate || self.reloadAnchorProgress == nil {
                    self.scrollSync.setRestoringReloadScroll(false)
                }
            }

            return true
        }

        func dropAwareWebViewDidChangeTargeting(_ update: DropTargetingUpdate) {
            onDropTargetedChange(update)
        }

        func dropAwareWebViewCanAcceptDrop(_ fileURLs: [URL]) -> Bool {
            canAcceptDroppedFileURLs(fileURLs)
        }

        func dropAwareWebViewDidReceiveDrop(_ fileURLs: [URL]) {
            onDroppedFileURLs(fileURLs)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            let action = crashRecovery.handleTermination(
                logger: logger,
                diagnosticName: diagnosticName
            )

            switch action {
            case .alreadyLocked:
                break

            case .recover:
                if let htmlDocument = lastHTMLDocument {
                    logInfo("retrying web content load after first termination")
                    loadHTMLDocument(htmlDocument, in: webView)
                }

            case .lockedOut:
                onFatalCrash()
                loadFallbackMessage(
                    "Web content process stopped repeatedly while rendering markdown. " +
                        "Try reopening the file."
                )
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            scrollSync.cancelPendingRestore()
            crashRecovery.lock()
            logError("navigation failed: \(error.localizedDescription)")
            onFatalCrash()
            loadFallbackMessage("Failed to render markdown: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            scrollSync.cancelPendingRestore()
            crashRecovery.lock()
            logError("provisional navigation failed: \(error.localizedDescription)")
            onFatalCrash()
            loadFallbackMessage("Failed to load markdown preview: \(error.localizedDescription)")
        }

        func handleChangedRegionNavigationIfNeeded(
            _ request: ChangedRegionNavigationRequest?,
            in webView: WKWebView
        ) {
            guard let request else {
                return
            }

            guard lastChangedRegionNavigationRequestID != request.id else {
                return
            }

            lastChangedRegionNavigationRequestID = request.id

            guard hasCompletedFirstLoad else {
                pendingChangedRegionNavigationRequest = request
                return
            }

            performChangedRegionNavigation(request, in: webView)
        }

        func handleScrollSyncRequestIfNeeded(
            _ request: ScrollSyncRequest?,
            in webView: WKWebView
        ) {
            scrollSync.handleScrollSyncRequestIfNeeded(
                request,
                in: webView,
                hasCompletedFirstLoad: hasCompletedFirstLoad
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logDebug("navigation finished")
            runPostLoadStatusProbe(in: webView)
            hasCompletedFirstLoad = true

            var hadPendingChangedRegionNavigation = false
            if let request = pendingChangedRegionNavigationRequest {
                pendingChangedRegionNavigationRequest = nil
                hadPendingChangedRegionNavigation = true
                performChangedRegionNavigation(request, in: webView)
            }

            var hadPendingScrollSync = false
            if !hadPendingChangedRegionNavigation, let request = scrollSync.pendingScrollSyncRequest {
                hadPendingScrollSync = true
                scrollSync.consumePendingScrollSyncRequest()
                scrollSync.performScrollSync(request, in: webView)
            }

            _ = scrollSync.restoreAfterNavigationIfNeeded(
                in: webView,
                hadPendingChangedRegionNavigation: hadPendingChangedRegionNavigation,
                hadPendingScrollSync: hadPendingScrollSync
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            switch classifyLinkAction(for: navigationAction, in: webView) {
            case .allow:
                decisionHandler(.allow)

            case .cancel:
                decisionHandler(.cancel)

            case let .openExternal(url):
                _ = NSWorkspace.shared.open(url)
                decisionHandler(.cancel)

            case let .scrollToFragment(fragment):
                scrollToFragment(fragment, in: webView)
                decisionHandler(.cancel)
            }
        }

        private func loadFallbackMessage(_ message: String) {
            scrollSync.cancelPendingRestore()
            logError("loading fallback message: \(message)")
            let fallbackHTML = """
            <html>
              <body style=\"font-family: -apple-system, sans-serif; margin: 24px;\">
                <h3>Preview unavailable</h3>
                <p>\(escapeHTML(message))</p>
              </body>
            </html>
            """
            webView?.loadHTMLString(fallbackHTML, baseURL: nil)
        }

        private func performChangedRegionNavigation(
            _ request: ChangedRegionNavigationRequest,
            in webView: WKWebView
        ) {
            let script = "window.__minimarkNavigateChangedRegion && window.__minimarkNavigateChangedRegion('\(request.direction.rawValue)');"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self, let error else {
                    return
                }

                self.logError("changed-region navigation failed: \(error.localizedDescription)")
            }
        }

        private func classifyLinkAction(
            for navigationAction: WKNavigationAction,
            in webView: WKWebView
        ) -> LinkAction {
            guard navigationAction.navigationType == .linkActivated else {
                return .allow
            }

            guard let url = navigationAction.request.url else {
                return .allow
            }

            if let fragment = inPageFragment(for: url, in: webView) {
                return .scrollToFragment(fragment)
            }

            if isSafeExternalURL(url) {
                return .openExternal(url)
            }

            return .cancel
        }

        private func inPageFragment(for targetURL: URL, in webView: WKWebView) -> String? {
            guard let fragment = targetURL.fragment, !fragment.isEmpty else {
                return nil
            }

            guard let currentURL = webView.url else {
                // If the current document URL is not yet available, only treat bare
                // fragment links as in-page anchors.
                let isBareFragment =
                    targetURL.scheme == nil &&
                    targetURL.host == nil &&
                    (targetURL.path.isEmpty || targetURL.path == "/")
                return isBareFragment ? fragment : nil
            }

            return isSameDocumentURL(targetURL, currentURL) ? fragment : nil
        }

        private func isSameDocumentURL(_ lhs: URL, _ rhs: URL) -> Bool {
            var lhsComponents = URLComponents(url: lhs, resolvingAgainstBaseURL: false)
            var rhsComponents = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
            lhsComponents?.fragment = nil
            rhsComponents?.fragment = nil
            return lhsComponents?.string == rhsComponents?.string
        }

        private func isSafeExternalURL(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else {
                return false
            }

            switch scheme {
            case "http", "https", "mailto", "file":
                return true
            default:
                return false
            }
        }

        private func scrollToFragment(_ fragment: String, in webView: WKWebView) {
            let fragmentLiteral = javaScriptStringLiteral(fragment)
            let script = """
            (() => {
              const original = \(fragmentLiteral);
              if (!original) return false;
              const candidates = [original];
              try {
                const decoded = decodeURIComponent(original);
                if (decoded !== original) candidates.push(decoded);
              } catch (_) {}

              for (const value of candidates) {
                const byId = document.getElementById(value);
                if (byId) {
                  byId.scrollIntoView({ block: 'start', inline: 'nearest' });
                  return true;
                }

                const byName = document.getElementsByName(value);
                if (byName && byName.length > 0) {
                  byName[0].scrollIntoView({ block: 'start', inline: 'nearest' });
                  return true;
                }
              }

              return false;
            })();
            """

            webView.evaluateJavaScript(script)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == MarkdownWebView.sourceEditMessageName,
               let payload = message.body as? [String: Any],
               let markdown = payload["markdown"] as? String {
                onSourceEdit(markdown)
                return
            }

            if message.name == MarkdownWebView.sourceEditorDiagnosticMessageName,
               let payload = message.body as? [String: Any],
               let eventName = payload["event"] as? String {
                let metaKey = (payload["metaKey"] as? Bool) ?? false
                let ctrlKey = (payload["ctrlKey"] as? Bool) ?? false
                let shiftKey = (payload["shiftKey"] as? Bool) ?? false
                let altKey = (payload["altKey"] as? Bool) ?? false
                logDiagnostic(
                    "source editor event=\(eventName) meta=\(metaKey) ctrl=\(ctrlKey) shift=\(shiftKey) alt=\(altKey)"
                )
                return
            }

            guard message.name == MarkdownWebView.scrollSyncMessageName,
                  let payload = message.body as? [String: Any],
                  let progress = payload["progress"] as? Double else {
                return
            }

            let offsetY = payload["offsetY"] as? Double
            let maxY = payload["maxY"] as? Double
            let suppressionToken = (payload["suppressionToken"] as? NSNumber)?.intValue

            if let observation = scrollSync.handleScrollObservationMessage(
                offsetY: offsetY,
                maxY: maxY,
                progress: progress,
                suppressionToken: suppressionToken
            ) {
                onScrollSyncObservation(observation)
            }
        }

        private func captureVisibleSnapshot(
            in webView: WKWebView,
            completion: @escaping (NSImage?) -> Void
        ) {
            webView.takeSnapshot(with: nil) { image, _ in
                completion(image)
            }
        }

        private func extractRuntimePayloadBase64(from htmlDocument: String) -> String? {
            extractMetaContent(named: "minimark-runtime-payload-base64", from: htmlDocument)
        }

        private func extractRuntimeCSSBase64(from htmlDocument: String) -> String? {
            extractMetaContent(named: "minimark-runtime-css-base64", from: htmlDocument)
        }

        private func extractRuntimeThemeJSBase64(from htmlDocument: String) -> String? {
            extractMetaContent(named: "minimark-runtime-theme-js-base64", from: htmlDocument)
        }

        private func extractMetaContent(named name: String, from htmlDocument: String) -> String? {
            let marker = #"<meta name=""# + name + #"" content=""#
            guard let markerRange = htmlDocument.range(of: marker) else {
                return nil
            }

            let payloadStart = markerRange.upperBound
            guard let payloadEnd = htmlDocument[payloadStart...].firstIndex(of: "\"") else {
                return nil
            }

            return String(htmlDocument[payloadStart..<payloadEnd])
        }

        private func runPostLoadStatusProbe(in webView: WKWebView) {
            guard let postLoadStatusScript else {
                return
            }

            webView.evaluateJavaScript(postLoadStatusScript) { [weak self] result, error in
                guard let self else {
                    return
                }

                if let error {
                    self.logDebug("post-load status probe failed: \(error.localizedDescription)")
                    self.onPostLoadStatus(nil)
                    return
                }

                let status = result as? String
                if let status {
                    self.logDebug("post-load status: \(status)")
                } else {
                    self.logDebug("post-load status probe returned no string status")
                }
                self.onPostLoadStatus(status)
            }
        }

        private func logDebug(_ message: String) {
            guard Self.verboseDiagnosticsEnabled else {
                return
            }
            logger.debug("[\(self.diagnosticName, privacy: .public)] [\(self.lastDocumentIdentity ?? "none", privacy: .public)] \(message, privacy: .public)")
        }

        private func logInfo(_ message: String) {
            guard Self.verboseDiagnosticsEnabled else {
                return
            }
            logger.info("[\(self.diagnosticName, privacy: .public)] [\(self.lastDocumentIdentity ?? "none", privacy: .public)] \(message, privacy: .public)")
        }

        private func logDiagnostic(_ message: String) {
            logger.info("[\(self.diagnosticName, privacy: .public)] [\(self.lastDocumentIdentity ?? "none", privacy: .public)] \(message, privacy: .public)")
        }

        private func logError(_ message: String) {
            logger.error("[\(self.diagnosticName, privacy: .public)] [\(self.lastDocumentIdentity ?? "none", privacy: .public)] \(message, privacy: .public)")
        }

        private func javaScriptStringLiteral(_ value: String) -> String {
            guard
                let data = try? JSONSerialization.data(withJSONObject: [value]),
                let jsonArray = String(data: data, encoding: .utf8),
                jsonArray.count >= 2
            else {
                return "\"\""
            }

            // JSON array format is ["value"], so trim the surrounding brackets.
            return String(jsonArray.dropFirst().dropLast())
        }

        private func escapeHTML(_ text: String) -> String {
            text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }
    }
}

protocol DropAwareWKWebViewDelegate: AnyObject {
    func dropAwareWebViewDidChangeTargeting(_ update: DropTargetingUpdate)
    func dropAwareWebViewCanAcceptDrop(_ fileURLs: [URL]) -> Bool
    func dropAwareWebViewDidReceiveDrop(_ fileURLs: [URL])
}

final class MarkdownWebContainerView: NSView {
    let webView: DropAwareWKWebView

    private let reloadSnapshotOverlayView: NSImageView = {
        let imageView = NSImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.isHidden = true
        return imageView
    }()

    init(webView: DropAwareWKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        addSubview(reloadSnapshotOverlayView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            reloadSnapshotOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            reloadSnapshotOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            reloadSnapshotOverlayView.topAnchor.constraint(equalTo: topAnchor),
            reloadSnapshotOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showReloadSnapshotOverlay(_ image: NSImage) {
        reloadSnapshotOverlayView.image = image
        reloadSnapshotOverlayView.isHidden = false
        webView.alphaValue = 0
    }

    func hideReloadSnapshotOverlay() {
        webView.alphaValue = 1
        reloadSnapshotOverlayView.isHidden = true
        reloadSnapshotOverlayView.image = nil
    }
}

final class DropAwareWKWebView: WKWebView {
    weak var dropDelegate: DropAwareWKWebViewDelegate?

    private static let clearedDropTargetingUpdate = DropTargetingUpdate(
        isTargeted: false,
        droppedFileURLs: [],
        containsDirectoryHint: false,
        canDrop: false
    )

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let update = notifyDropTargetingUpdate(from: sender)
        return update.canDrop ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let update = notifyDropTargetingUpdate(from: sender)
        return update.canDrop ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        notifyDropTargetingCleared()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        notifyDropTargetingCleared()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let update = dragTargetingUpdate(from: sender)
        notifyDropTargetingCleared()
        guard update.canDrop else {
            return false
        }

        dropDelegate?.dropAwareWebViewDidReceiveDrop(update.droppedFileURLs)
        return true
    }

    private func notifyDropTargetingUpdate(from draggingInfo: NSDraggingInfo) -> DropTargetingUpdate {
        let update = dragTargetingUpdate(from: draggingInfo)
        dropDelegate?.dropAwareWebViewDidChangeTargeting(update)
        return update
    }

    private func notifyDropTargetingCleared() {
        dropDelegate?.dropAwareWebViewDidChangeTargeting(Self.clearedDropTargetingUpdate)
    }

    private func dragTargetingUpdate(from draggingInfo: NSDraggingInfo) -> DropTargetingUpdate {
        let fileURLs = droppedFileURLs(from: draggingInfo)
        let hasFileURLs = !fileURLs.isEmpty
        let containsDirectoryHint = ReaderFileRouting.containsLikelyDirectoryPath(in: fileURLs)
        let canDrop = hasFileURLs && (dropDelegate?.dropAwareWebViewCanAcceptDrop(fileURLs) ?? true)

        return DropTargetingUpdate(
            isTargeted: hasFileURLs,
            droppedFileURLs: fileURLs,
            containsDirectoryHint: containsDirectoryHint,
            canDrop: canDrop
        )
    }

    private func droppedFileURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] else {
            return []
        }

        return urls.map(\.standardizedFileURL)
    }
}
