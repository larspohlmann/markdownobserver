import SwiftUI
import WebKit
import AppKit
import OSLog

struct ChangedRegionNavigationRequest: Equatable {
    let id: Int
    let direction: ReaderChangedRegionNavigationDirection
}

struct ScrollSyncRequest: Equatable {
        let id: Int
        let progress: Double
}

struct ScrollSyncObservation: Equatable {
        let progress: Double
        let isProgrammatic: Bool
}

struct DropTargetingUpdate: Equatable {
    let isTargeted: Bool
    let droppedFileURLs: [URL]
    let canDrop: Bool
}

struct MarkdownWebView: NSViewRepresentable {
        private static let scrollSyncMessageName = "minimarkScrollSync"
    private static let sourceEditMessageName = "minimarkSourceEdit"
    private static let sourceEditorDiagnosticMessageName = "minimarkSourceEditorDiagnostic"
        private static let scrollSyncObserverScript = """
        (() => {
            if (window.__minimarkScrollSyncInstalled) {
                return;
            }
            window.__minimarkScrollSyncInstalled = true;
            window.__minimarkScrollSyncSuppressionToken = null;

            function activeScrollTarget() {
                const sourceEditor = document.querySelector('.minimark-source-editor');
                if (sourceEditor) {
                    return {
                        kind: 'element',
                        element: sourceEditor,
                        viewportHeight: sourceEditor.clientHeight || 0
                    };
                }

                const element = document.scrollingElement || document.documentElement || document.body;
                if (!element) {
                    return null;
                }

                return {
                    kind: 'page',
                    element,
                    viewportHeight: window.innerHeight || element.clientHeight || 0
                };
            }

            function currentScrollPayload() {
                const target = activeScrollTarget();
                if (!target || !target.element) {
                    return null;
                }

                const element = target.element;
                const maxY = Math.max(0, element.scrollHeight - target.viewportHeight);
                const rawOffsetY = target.kind === 'page'
                    ? (window.scrollY || element.scrollTop || 0)
                    : (element.scrollTop || 0);
                const offsetY = Math.max(0, Math.min(rawOffsetY, maxY));
                const progress = maxY > 0 ? Math.min(Math.max(offsetY / maxY, 0), 1) : 0;
                return {
                    offsetY,
                    maxY,
                    progress,
                    targetKind: target.kind,
                    suppressionToken: window.__minimarkScrollSyncSuppressionToken
                };
            }

            let scheduledState = { value: false };
            function publishScrollState() {
                scheduledState.value = false;
                const payload = currentScrollPayload();
                if (!payload) {
                    return;
                }

                try {
                    window.webkit.messageHandlers.minimarkScrollSync.postMessage(payload);
                } catch (_) {}
            }

            function schedulePublish() {
                if (scheduledState.value) {
                    return;
                }
                scheduledState.value = true;
                window.requestAnimationFrame(publishScrollState);
            }

            window.addEventListener('scroll', schedulePublish, { passive: true, capture: true });
            window.addEventListener('resize', schedulePublish, { passive: true });
            window.addEventListener('load', schedulePublish);
            const mutationObserver = new MutationObserver(schedulePublish);
            mutationObserver.observe(document.documentElement, {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['class', 'style']
            });

            setTimeout(schedulePublish, 0);
        })();
        """

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

        private struct ScrollSnapshot {
            let offsetY: Double
            let maxOffsetY: Double

            var progress: Double {
                guard maxOffsetY > 0 else {
                    return 0
                }
                return min(max(offsetY / maxOffsetY, 0), 1)
            }

            var wasNearBottom: Bool {
                guard maxOffsetY > 0 else {
                    return false
                }
                return (maxOffsetY - offsetY) <= 2
            }
        }

        private enum LinkAction {
            case allow
            case cancel
            case openExternal(URL)
            case scrollToFragment(String)
        }

        private weak var webView: WKWebView?
        private weak var containerView: MarkdownWebContainerView?
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "minimark", category: "MarkdownWebView")
        var lastHTMLDocument: String?
        var diagnosticName: String = "reader-web"
        var postLoadStatusScript: String?
        private var lastDocumentIdentity: String?
        private var lastTerminationAt: Date?
        private var rapidTerminationCount = 0
        private var isCrashRecoveryLocked = false
        private var hasCompletedFirstLoad = false
        private var latestReloadRequestID = 0
        private var pendingScrollSnapshot: ScrollSnapshot?
        private var lastObservedScrollSnapshot: ScrollSnapshot?
        private var isRestoringReloadScroll = false
        private var pendingReloadAnchorProgress: Double?
        private var restoreWorkItem: DispatchWorkItem?
        private var lastReloadToken: Int?
        private var lastChangedRegionNavigationRequestID: Int?
        private var pendingChangedRegionNavigationRequest: ChangedRegionNavigationRequest?
        private var lastScrollSyncRequestID: Int?
        private var lastAppliedScrollSyncRequestID: Int?
        private var pendingScrollSyncRequest: ScrollSyncRequest?
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
        }

        func prepareForDocumentChangeIfNeeded(_ identity: String?) -> Bool {
            guard identity != lastDocumentIdentity else {
                return false
            }

            lastDocumentIdentity = identity
            hasCompletedFirstLoad = false
            isCrashRecoveryLocked = false
            cancelPendingRestore()
            pendingChangedRegionNavigationRequest = nil
            pendingScrollSyncRequest = nil
            lastScrollSyncRequestID = nil
            lastAppliedScrollSyncRequestID = nil
            lastObservedScrollSnapshot = nil
            isRestoringReloadScroll = false
            pendingReloadAnchorProgress = nil
            logDebug("document change detected")
            return true
        }

        func prepareForRetryIfNeeded(_ reloadToken: Int, in webView: WKWebView) {
            guard lastReloadToken != reloadToken else {
                return
            }

            lastReloadToken = reloadToken
            isCrashRecoveryLocked = false
            rapidTerminationCount = 0
            lastTerminationAt = nil
            hasCompletedFirstLoad = false
            cancelPendingRestore()
            pendingChangedRegionNavigationRequest = nil
            pendingScrollSyncRequest = nil
            lastScrollSyncRequestID = nil
            lastAppliedScrollSyncRequestID = nil
            lastObservedScrollSnapshot = nil
            isRestoringReloadScroll = false
            pendingReloadAnchorProgress = nil
            logInfo("reload requested by retry token")

            if let lastHTMLDocument {
                loadHTMLDocument(lastHTMLDocument, in: webView)
            }
        }

        func loadHTMLDocument(_ htmlDocument: String, in webView: WKWebView) {
            guard !isCrashRecoveryLocked else {
                logInfo("load skipped because crash recovery is locked")
                return
            }

            latestReloadRequestID += 1
            let requestID = latestReloadRequestID
            cancelPendingRestore()
            logDebug("loading HTML document")

            guard hasCompletedFirstLoad else {
                pendingScrollSnapshot = nil
                containerView?.hideReloadSnapshotOverlay()
                webView.loadHTMLString(htmlDocument, baseURL: Bundle.main.bundleURL)
                return
            }

            captureScrollSnapshot(in: webView) { [weak self, weak webView] snapshot in
                guard
                    let self,
                    let webView,
                    self.latestReloadRequestID == requestID
                else {
                    return
                }

                self.pendingScrollSnapshot = snapshot ?? self.lastObservedScrollSnapshot
                self.pendingReloadAnchorProgress = self.reloadAnchorProgress
                self.isRestoringReloadScroll = self.pendingScrollSnapshot != nil || self.pendingReloadAnchorProgress != nil
                self.captureVisibleSnapshot(in: webView) { [weak self, weak webView] image in
                    guard
                        let self,
                        let webView,
                        self.latestReloadRequestID == requestID
                    else {
                        return
                    }

                    if self.isRestoringReloadScroll,
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

            let anchorProgressLiteral: String
            if let reloadAnchorProgress {
                anchorProgressLiteral = String(min(max(reloadAnchorProgress, 0), 1))
            } else {
                anchorProgressLiteral = "null"
            }

            isRestoringReloadScroll = reloadAnchorProgress != nil
            let script = """
            (() => {
                            if (typeof window.__minimarkApplyRuntimeCSS === 'function') {
                                window.__minimarkApplyRuntimeCSS(
                                    \(javaScriptStringLiteral(cssBase64))
                                );
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
                    self.isRestoringReloadScroll = false
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
            guard !isCrashRecoveryLocked else {
                logInfo("web content process terminated while recovery lock was active")
                return
            }

            let now = Date()
            if let lastTerminationAt, now.timeIntervalSince(lastTerminationAt) < 5 {
                rapidTerminationCount += 1
            } else {
                rapidTerminationCount = 1
            }
            self.lastTerminationAt = now
            logInfo("web content process terminated; rapidCount=\(rapidTerminationCount)")

            if rapidTerminationCount <= 1, let htmlDocument = lastHTMLDocument {
                logInfo("retrying web content load after first termination")
                loadHTMLDocument(htmlDocument, in: webView)
                return
            }

            // Stop automatic reloads until the user changes document context.
            isCrashRecoveryLocked = true
            onFatalCrash()

            loadFallbackMessage(
                "Web content process stopped repeatedly while rendering markdown. " +
                    "Try reopening the file."
            )
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            cancelPendingRestore()
            isCrashRecoveryLocked = true
            logError("navigation failed: \(error.localizedDescription)")
            onFatalCrash()
            loadFallbackMessage("Failed to render markdown: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            cancelPendingRestore()
            isCrashRecoveryLocked = true
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
            guard let request else {
                return
            }

            guard lastScrollSyncRequestID != request.id else {
                return
            }

            lastScrollSyncRequestID = request.id

            guard hasCompletedFirstLoad else {
                pendingScrollSyncRequest = request
                return
            }

            performScrollSync(request, in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logDebug("navigation finished")
            runPostLoadStatusProbe(in: webView)
            hasCompletedFirstLoad = true

            if let pendingChangedRegionNavigationRequest {
                self.pendingChangedRegionNavigationRequest = nil
                pendingScrollSnapshot = nil
                pendingReloadAnchorProgress = nil
                isRestoringReloadScroll = false
                performChangedRegionNavigation(pendingChangedRegionNavigationRequest, in: webView)
                return
            }

            if let pendingScrollSyncRequest {
                self.pendingScrollSyncRequest = nil
                pendingScrollSnapshot = nil
                pendingReloadAnchorProgress = nil
                isRestoringReloadScroll = false
                performScrollSync(pendingScrollSyncRequest, in: webView)
                return
            }

            if let pendingReloadAnchorProgress {
                self.pendingReloadAnchorProgress = nil
                restoreScrollProgress(in: webView, to: pendingReloadAnchorProgress, attempt: 0)
                return
            }

            guard let snapshot = pendingScrollSnapshot else {
                isRestoringReloadScroll = false
                return
            }
            restoreScrollPosition(in: webView, using: snapshot, attempt: 0)
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
            cancelPendingRestore()
            containerView?.hideReloadSnapshotOverlay()
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

            if let offsetY = payload["offsetY"] as? Double,
               let maxY = payload["maxY"] as? Double {
                if !isRestoringReloadScroll {
                    lastObservedScrollSnapshot = ScrollSnapshot(offsetY: offsetY, maxOffsetY: maxY)
                }
            }

            if isRestoringReloadScroll {
                return
            }

            let suppressionToken = (payload["suppressionToken"] as? NSNumber)?.intValue
            let isProgrammatic = suppressionToken != nil && suppressionToken == lastAppliedScrollSyncRequestID
            onScrollSyncObservation(
                ScrollSyncObservation(
                    progress: min(max(progress, 0), 1),
                    isProgrammatic: isProgrammatic
                )
            )
        }

        private func captureScrollSnapshot(
            in webView: WKWebView,
            completion: @escaping (ScrollSnapshot?) -> Void
        ) {
                        let script = """
                        (() => {
                            const sourceEditor = document.querySelector('.minimark-source-editor');
                            if (sourceEditor) {
                                const maxY = Math.max(0, sourceEditor.scrollHeight - sourceEditor.clientHeight);
                                const y = Math.max(0, Math.min(sourceEditor.scrollTop || 0, maxY));
                                return { y, maxY };
                            }

                            const element = document.scrollingElement || document.documentElement || document.body;
                            if (!element) return null;
                            const maxY = Math.max(0, element.scrollHeight - window.innerHeight);
                            const y = Math.max(0, Math.min(window.scrollY || element.scrollTop || 0, maxY));
                            return { y, maxY };
                        })();
                        """

            webView.evaluateJavaScript(script) { result, _ in
                guard
                    let dict = result as? [String: Any],
                    let y = dict["y"] as? Double,
                    let maxY = dict["maxY"] as? Double
                else {
                    completion(nil)
                    return
                }

                completion(ScrollSnapshot(offsetY: y, maxOffsetY: maxY))
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

                private func performScrollSync(
                        _ request: ScrollSyncRequest,
                        in webView: WKWebView
                ) {
                        lastAppliedScrollSyncRequestID = request.id
                        let progress = min(max(request.progress, 0), 1)
                        let script = """
                        (() => {
                            const token = \(request.id);
                            const sourceEditor = document.querySelector('.minimark-source-editor');
                            if (sourceEditor) {
                                const maxY = Math.max(0, sourceEditor.scrollHeight - sourceEditor.clientHeight);
                                const target = Math.max(0, Math.min(maxY, \(progress) * maxY));
                                window.__minimarkScrollSyncSuppressionToken = token;
                                sourceEditor.scrollTop = target;
                                window.setTimeout(() => {
                                    if (window.__minimarkScrollSyncSuppressionToken === token) {
                                        window.__minimarkScrollSyncSuppressionToken = null;
                                    }
                                }, 120);
                                return { target, maxY };
                            }

                            const element = document.scrollingElement || document.documentElement || document.body;
                            if (!element) return null;
                            const maxY = Math.max(0, element.scrollHeight - window.innerHeight);
                            const target = Math.max(0, Math.min(maxY, \(progress) * maxY));
                            window.__minimarkScrollSyncSuppressionToken = token;
                            window.scrollTo(0, target);
                            window.setTimeout(() => {
                                if (window.__minimarkScrollSyncSuppressionToken === token) {
                                    window.__minimarkScrollSyncSuppressionToken = null;
                                }
                            }, 120);
                            return { target, maxY };
                        })();
                        """

                        webView.evaluateJavaScript(script) { [weak self] _, error in
                                guard let self else {
                                        return
                                }

                                if let error {
                                        self.logDebug("scroll sync failed: \(error.localizedDescription)")
                                }
                        }
                }

        private func restoreScrollPosition(
            in webView: WKWebView,
            using snapshot: ScrollSnapshot,
            attempt: Int
        ) {
                        let script = """
                        (() => {
                            const preferred = \(snapshot.offsetY);
                            const progress = \(snapshot.progress);
                            const nearBottom = \(snapshot.wasNearBottom ? "true" : "false");
                            const sourceEditor = document.querySelector('.minimark-source-editor');
                            if (sourceEditor) {
                                const maxY = Math.max(0, sourceEditor.scrollHeight - sourceEditor.clientHeight);
                                let target = Math.min(Math.max(preferred, 0), maxY);
                                if (nearBottom) {
                                    target = maxY;
                                } else if (preferred > maxY && progress > 0 && maxY > 0) {
                                    target = Math.min(maxY, Math.max(0, progress * maxY));
                                }

                                sourceEditor.scrollTop = target;
                                const actualY = sourceEditor.scrollTop || 0;
                                return { target, actualY, maxY };
                            }

                            const element = document.scrollingElement || document.documentElement || document.body;
                            if (!element) return null;
                            const maxY = Math.max(0, element.scrollHeight - window.innerHeight);
                            let target = Math.min(Math.max(preferred, 0), maxY);
                            if (nearBottom) {
                                target = maxY;
                            } else if (preferred > maxY && progress > 0 && maxY > 0) {
                                target = Math.min(maxY, Math.max(0, progress * maxY));
                            }

                            window.scrollTo(0, target);
                            const actualY = window.scrollY || element.scrollTop || 0;
                            return { target, actualY, maxY };
                        })();
                        """

            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard
                    let self,
                    let webView,
                    let dict = result as? [String: Any],
                    let target = dict["target"] as? Double,
                    let actualY = dict["actualY"] as? Double,
                    let maxY = dict["maxY"] as? Double
                else {
                    self?.pendingScrollSnapshot = nil
                    return
                }

                let remainingAttempts = 3
                let shouldRetryForLateLayout = attempt < remainingAttempts && (
                    abs(actualY - target) > 1.5 ||
                        (snapshot.offsetY > 0 && maxY == 0)
                )

                guard shouldRetryForLateLayout else {
                    self.lastObservedScrollSnapshot = ScrollSnapshot(offsetY: actualY, maxOffsetY: maxY)
                    self.isRestoringReloadScroll = false
                    self.pendingScrollSnapshot = nil
                    self.containerView?.hideReloadSnapshotOverlay()
                    return
                }

                let workItem = DispatchWorkItem { [weak self, weak webView] in
                    guard let self, let webView else {
                        return
                    }
                    self.restoreScrollPosition(in: webView, using: snapshot, attempt: attempt + 1)
                }
                self.restoreWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
            }
        }

        private func restoreScrollProgress(
            in webView: WKWebView,
            to progress: Double,
            attempt: Int
        ) {
            let clampedProgress = min(max(progress, 0), 1)
            let script = """
            (() => {
              const sourceEditor = document.querySelector('.minimark-source-editor');
              if (sourceEditor) {
                const maxY = Math.max(0, sourceEditor.scrollHeight - sourceEditor.clientHeight);
                const target = Math.max(0, Math.min(maxY, \(clampedProgress) * maxY));
                sourceEditor.scrollTop = target;
                const actualY = sourceEditor.scrollTop || 0;
                return { target, actualY, maxY };
              }

              const element = document.scrollingElement || document.documentElement || document.body;
              if (!element) return null;
              const maxY = Math.max(0, element.scrollHeight - window.innerHeight);
              const target = Math.max(0, Math.min(maxY, \(clampedProgress) * maxY));
              window.scrollTo(0, target);
              const actualY = window.scrollY || element.scrollTop || 0;
              return { target, actualY, maxY };
            })();
            """

            webView.evaluateJavaScript(script) { [weak self, weak webView] result, _ in
                guard
                    let self,
                    let webView,
                    let dict = result as? [String: Any],
                    let target = dict["target"] as? Double,
                    let actualY = dict["actualY"] as? Double,
                    let maxY = dict["maxY"] as? Double
                else {
                    self?.containerView?.hideReloadSnapshotOverlay()
                    self?.isRestoringReloadScroll = false
                    return
                }

                let remainingAttempts = 3
                let shouldRetryForLateLayout = attempt < remainingAttempts && abs(actualY - target) > 1.5

                guard shouldRetryForLateLayout else {
                    self.lastObservedScrollSnapshot = ScrollSnapshot(offsetY: actualY, maxOffsetY: maxY)
                    self.isRestoringReloadScroll = false
                    self.containerView?.hideReloadSnapshotOverlay()
                    return
                }

                let workItem = DispatchWorkItem { [weak self, weak webView] in
                    guard let self, let webView else {
                        return
                    }
                    self.restoreScrollProgress(in: webView, to: clampedProgress, attempt: attempt + 1)
                }
                self.restoreWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
            }
        }

        private func cancelPendingRestore() {
            restoreWorkItem?.cancel()
            restoreWorkItem = nil
            pendingScrollSnapshot = nil
            isRestoringReloadScroll = false
            pendingReloadAnchorProgress = nil
            containerView?.hideReloadSnapshotOverlay()
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
        let canDrop = hasFileURLs && (dropDelegate?.dropAwareWebViewCanAcceptDrop(fileURLs) ?? true)

        return DropTargetingUpdate(
            isTargeted: hasFileURLs,
            droppedFileURLs: fileURLs,
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
