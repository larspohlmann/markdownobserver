import Foundation
import Testing
import WebKit
@testable import minimark

struct WebViewScrollSyncControllerStateTests {

    // MARK: - ScrollSnapshot.progress

    @Test func snapshotProgressIsZeroWhenMaxIsZero() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 50, maxOffsetY: 0)
        #expect(snapshot.progress == 0)
    }

    @Test func snapshotProgressComputesCorrectly() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 50, maxOffsetY: 200)
        #expect(snapshot.progress == 0.25)
    }

    @Test func snapshotProgressClampedToOne() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 300, maxOffsetY: 200)
        #expect(snapshot.progress == 1.0)
    }

    // MARK: - ScrollSnapshot.wasNearBottom

    @Test func wasNearBottomTrueWhenWithinTwoPoints() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 198, maxOffsetY: 200)
        #expect(snapshot.wasNearBottom == true)
    }

    @Test func wasNearBottomFalseWhenFarFromBottom() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 100, maxOffsetY: 200)
        #expect(snapshot.wasNearBottom == false)
    }

    @Test func wasNearBottomFalseWhenMaxIsZero() {
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 0, maxOffsetY: 0)
        #expect(snapshot.wasNearBottom == false)
    }

    // MARK: - resetForDocumentChange

    @MainActor
    @Test func resetForDocumentChangeClearsAllState() {
        let controller = WebViewScrollSyncController()
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 100, maxOffsetY: 400)
        controller.prepareForReloadRestore(
            snapshot: snapshot,
            fallbackSnapshot: nil,
            reloadAnchorProgress: 0.5
        )
        controller.setRestoringReloadScroll(true)
        controller.resetForDocumentChange()
        #expect(controller.pendingScrollSnapshot == nil)
        #expect(controller.lastObservedScrollSnapshot == nil)
        #expect(controller.isRestoringReloadScroll == false)
        #expect(controller.pendingReloadAnchorProgress == nil)
        #expect(controller.pendingScrollSyncRequest == nil)
        #expect(controller.lastScrollSyncRequestID == nil)
        #expect(controller.lastAppliedScrollSyncRequestID == nil)
    }

    // MARK: - prepareForReloadRestore

    @Test func prepareForReloadRestoreSetsSnapshotAndProgress() {
        let controller = WebViewScrollSyncController()
        let snapshot = WebViewScrollSyncController.ScrollSnapshot(offsetY: 80, maxOffsetY: 400)
        controller.prepareForReloadRestore(
            snapshot: snapshot,
            fallbackSnapshot: nil,
            reloadAnchorProgress: 0.4
        )
        #expect(controller.pendingScrollSnapshot?.offsetY == 80)
        #expect(controller.pendingReloadAnchorProgress == 0.4)
        #expect(controller.isRestoringReloadScroll == true)
    }

    @Test func prepareForReloadRestoreUsesFallbackWhenSnapshotIsNil() {
        let controller = WebViewScrollSyncController()
        let fallback = WebViewScrollSyncController.ScrollSnapshot(offsetY: 30, maxOffsetY: 300)
        controller.prepareForReloadRestore(
            snapshot: nil,
            fallbackSnapshot: fallback,
            reloadAnchorProgress: nil
        )
        #expect(controller.pendingScrollSnapshot?.offsetY == 30)
        #expect(controller.isRestoringReloadScroll == true)
    }

    @Test func prepareForReloadRestoreNotRestoringWhenBothNil() {
        let controller = WebViewScrollSyncController()
        controller.prepareForReloadRestore(
            snapshot: nil,
            fallbackSnapshot: nil,
            reloadAnchorProgress: nil
        )
        #expect(controller.pendingScrollSnapshot == nil)
        #expect(controller.isRestoringReloadScroll == false)
    }

    // MARK: - handleScrollObservationMessage

    @Test func handleScrollObservationUpdatesLastSnapshot() {
        let controller = WebViewScrollSyncController()
        let result = controller.handleScrollObservationMessage(
            offsetY: 120,
            maxY: 400,
            progress: 0.3,
            suppressionToken: nil
        )
        #expect(controller.lastObservedScrollSnapshot?.offsetY == 120)
        #expect(result != nil)
    }

    @Test func handleScrollObservationSuppressedDuringRestore() {
        let controller = WebViewScrollSyncController()
        controller.setRestoringReloadScroll(true)
        let result = controller.handleScrollObservationMessage(
            offsetY: 120,
            maxY: 400,
            progress: 0.3,
            suppressionToken: nil
        )
        // Snapshot should NOT be updated during restore
        #expect(controller.lastObservedScrollSnapshot == nil)
        #expect(result == nil)
    }

    @Test func handleScrollObservationClampsProgress() {
        let controller = WebViewScrollSyncController()
        let result = controller.handleScrollObservationMessage(
            offsetY: nil,
            maxY: nil,
            progress: 1.5,
            suppressionToken: nil
        )
        #expect(result?.progress == 1.0)
    }

    // MARK: - consumePendingScrollSyncRequest

    @MainActor
    @Test func consumePendingScrollSyncRequestClearsRequest() {
        let controller = WebViewScrollSyncController()
        let webView = WKWebView()
        let request = ScrollSyncRequest(id: 42, progress: 0.5)
        controller.handleScrollSyncRequestIfNeeded(request, in: webView, hasCompletedFirstLoad: false)
        #expect(controller.pendingScrollSyncRequest != nil)
        controller.consumePendingScrollSyncRequest()
        #expect(controller.pendingScrollSyncRequest == nil)
    }

    @MainActor
    @Test func nilRequestIsIgnored() {
        let controller = WebViewScrollSyncController()
        let webView = WKWebView()
        controller.handleScrollSyncRequestIfNeeded(nil, in: webView, hasCompletedFirstLoad: false)
        #expect(controller.pendingScrollSyncRequest == nil)
        #expect(controller.lastScrollSyncRequestID == nil)
    }
}
