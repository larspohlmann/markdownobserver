import Combine
import Foundation

@MainActor
final class SplitScrollCoordinator: ObservableObject {
    @Published private var previewRequest: ScrollSyncRequest?
    @Published private var sourceRequest: ScrollSyncRequest?

    private var nextRequestID = 0
    private var lastRequestedProgressByRole: [DocumentSurfaceRole: Double] = [:]
    private var lastObservedProgressByRole: [DocumentSurfaceRole: Double] = [:]
    private var previewBounceBackSuppressedUntil: Date?

    func request(for role: DocumentSurfaceRole) -> ScrollSyncRequest? {
        switch role {
        case .preview:
            return previewRequest
        case .source:
            return sourceRequest
        }
    }

    /// Temporarily prevents scroll-sync observations from bouncing back to the
    /// preview pane. Called when a changed-region navigation scrolls the preview
    /// to an exact element position — the source pane may still sync forward,
    /// but its response must not override the navigation scroll.
    func suppressPreviewBounceBack(for duration: TimeInterval = 0.6) {
        previewBounceBackSuppressedUntil = Date().addingTimeInterval(duration)
    }

    func handleObservation(
        _ observation: ScrollSyncObservation,
        from role: DocumentSurfaceRole,
        shouldSync: Bool
    ) {
        lastObservedProgressByRole[role] = observation.progress

        guard shouldSync, !observation.isProgrammatic else {
            return
        }

        let targetRole = role.counterpart

        if targetRole == .preview,
           let suppressedUntil = previewBounceBackSuppressedUntil,
           Date() < suppressedUntil {
            return
        }

        if let lastProgress = lastRequestedProgressByRole[targetRole],
           abs(lastProgress - observation.progress) < 0.003 {
            return
        }

        nextRequestID += 1
        let request = ScrollSyncRequest(id: nextRequestID, progress: observation.progress)
        lastRequestedProgressByRole[targetRole] = observation.progress

        switch targetRole {
        case .preview:
            previewRequest = request
        case .source:
            sourceRequest = request
        }
    }

    func latestObservedProgress(for role: DocumentSurfaceRole) -> Double? {
        lastObservedProgressByRole[role]
    }

    func reset() {
        previewRequest = nil
        sourceRequest = nil
        lastRequestedProgressByRole.removeAll()
        lastObservedProgressByRole.removeAll()
        previewBounceBackSuppressedUntil = nil
    }
}
