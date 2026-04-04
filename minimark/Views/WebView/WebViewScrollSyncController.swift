import Foundation
import WebKit

/// Owns all scroll-sync state for the ``MarkdownWebView`` Coordinator:
/// snapshot capture, reload-scroll restoration, progress-based scroll sync,
/// and deduplication of scroll-sync requests.
final class WebViewScrollSyncController {

    struct ScrollSnapshot {
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

    // MARK: - Scroll restore state

    private(set) var pendingScrollSnapshot: ScrollSnapshot?
    private(set) var lastObservedScrollSnapshot: ScrollSnapshot?
    private(set) var isRestoringReloadScroll = false
    private(set) var pendingReloadAnchorProgress: Double?
    private var restoreWorkItem: DispatchWorkItem?

    // MARK: - Scroll sync request deduplication

    private(set) var lastScrollSyncRequestID: Int?
    private(set) var lastAppliedScrollSyncRequestID: Int?
    private(set) var pendingScrollSyncRequest: ScrollSyncRequest?

    /// A reference to the container view, used to show/hide the snapshot overlay
    /// during scroll restoration.
    weak var containerView: MarkdownWebContainerView?

    // MARK: - Reset

    /// Clears all scroll state. Called when the document identity changes.
    func resetForDocumentChange() {
        cancelPendingRestore()
        pendingScrollSyncRequest = nil
        lastScrollSyncRequestID = nil
        lastAppliedScrollSyncRequestID = nil
        lastObservedScrollSnapshot = nil
        isRestoringReloadScroll = false
        pendingReloadAnchorProgress = nil
    }

    /// Clears the pending scroll sync request after it has been consumed
    /// (e.g. after navigation finishes and the request is dispatched).
    func consumePendingScrollSyncRequest() {
        pendingScrollSyncRequest = nil
    }

    // MARK: - Scroll sync request handling

    /// Evaluates whether a scroll-sync request needs execution. Deduplicates by
    /// request ID and defers execution until after the first navigation finishes.
    ///
    /// - Parameters:
    ///   - request: The incoming request, or nil.
    ///   - webView: The web view to evaluate JavaScript in.
    ///   - hasCompletedFirstLoad: Whether the web view has finished its initial load.
    func handleScrollSyncRequestIfNeeded(
        _ request: ScrollSyncRequest?,
        in webView: WKWebView,
        hasCompletedFirstLoad: Bool
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

    /// Applies a scroll-sync request by scrolling the web view to the given
    /// progress fraction.
    func performScrollSync(
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
                // Log is best-effort; the Coordinator owns the logger.
                _ = error
            }
        }
    }

    // MARK: - Scroll snapshot capture

    /// Reads the current scroll position from the web view via JavaScript.
    func captureScrollSnapshot(
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

    // MARK: - Scroll restoration after reload

    /// Prepares for a scroll restore cycle before a full HTML reload. Captures
    /// the current snapshot and anchor progress so they can be restored after
    /// navigation finishes.
    func prepareForReloadRestore(
        snapshot: ScrollSnapshot?,
        fallbackSnapshot: ScrollSnapshot?,
        reloadAnchorProgress: Double?
    ) {
        pendingScrollSnapshot = snapshot ?? fallbackSnapshot
        pendingReloadAnchorProgress = reloadAnchorProgress
        isRestoringReloadScroll = pendingScrollSnapshot != nil || pendingReloadAnchorProgress != nil
    }

    /// Called by the Coordinator when navigation finishes. Applies any pending
    /// scroll restoration and clears pending state.
    ///
    /// - Parameters:
    ///   - webView: The web view to scroll.
    ///   - hadPendingChangedRegionNavigation: True if a changed-region navigation
    ///     was executed instead, which cancels scroll restoration.
    ///   - hadPendingScrollSync: True if a scroll-sync request was executed
    ///     instead, which cancels scroll restoration.
    /// - Returns: `true` if scroll restoration was handled (or skipped because
    ///   another navigation took priority).
    func restoreAfterNavigationIfNeeded(
        in webView: WKWebView,
        hadPendingChangedRegionNavigation: Bool,
        hadPendingScrollSync: Bool
    ) -> Bool {
        if hadPendingChangedRegionNavigation || hadPendingScrollSync {
            pendingScrollSnapshot = nil
            pendingReloadAnchorProgress = nil
            isRestoringReloadScroll = false
            return true
        }

        if let pendingReloadAnchorProgress {
            self.pendingReloadAnchorProgress = nil
            restoreScrollProgress(in: webView, to: pendingReloadAnchorProgress, attempt: 0)
            return true
        }

        guard let snapshot = pendingScrollSnapshot else {
            isRestoringReloadScroll = false
            return false
        }

        restoreScrollPosition(in: webView, using: snapshot, attempt: 0)
        return true
    }

    /// Restores scroll position to match a previously captured snapshot.
    /// Retries up to 3 times to handle late-layout scenarios.
    func restoreScrollPosition(
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

    /// Restores scroll to a specific progress value (0...1).
    /// Retries up to 3 times to handle late-layout scenarios.
    func restoreScrollProgress(
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

    // MARK: - Scroll message handling

    /// Processes a scroll-sync observation message from JavaScript. Updates the
    /// last observed snapshot and determines whether to suppress the observation
    /// (during scroll restoration or programmatic scrolls).
    ///
    /// - Parameters:
    ///   - offsetY: The current scroll offset.
    ///   - maxY: The maximum scrollable offset.
    ///   - progress: The scroll progress (0...1).
    ///   - suppressionToken: The suppression token from the JS message, if any.
    /// - Returns: A ``ScrollSyncObservation`` if one should be forwarded to the
    ///   parent, or nil if the observation should be suppressed.
    func handleScrollObservationMessage(
        offsetY: Double?,
        maxY: Double?,
        progress: Double,
        suppressionToken: Int?
    ) -> ScrollSyncObservation? {
        if let offsetY, let maxY {
            if !isRestoringReloadScroll {
                lastObservedScrollSnapshot = ScrollSnapshot(offsetY: offsetY, maxOffsetY: maxY)
            }
        }

        if isRestoringReloadScroll {
            return nil
        }

        let isProgrammatic = suppressionToken != nil && suppressionToken == lastAppliedScrollSyncRequestID
        return ScrollSyncObservation(
            progress: min(max(progress, 0), 1),
            isProgrammatic: isProgrammatic
        )
    }

    // MARK: - In-place update support

    /// Updates `isRestoringReloadScroll` for in-place content updates.
    func setRestoringReloadScroll(_ value: Bool) {
        isRestoringReloadScroll = value
    }

    // MARK: - Internal

    /// Cancels any pending scroll restore work item and resets restore state.
    func cancelPendingRestore() {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        pendingScrollSnapshot = nil
        isRestoringReloadScroll = false
        pendingReloadAnchorProgress = nil
        containerView?.hideReloadSnapshotOverlay()
    }
}
