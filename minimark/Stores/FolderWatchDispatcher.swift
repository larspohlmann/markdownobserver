import Foundation
import Observation

@MainActor
@Observable
final class FolderWatchDispatcher {
    private(set) var activeFolderWatchSession: FolderWatchSession?
    var lastWatchedFolderEventAt: Date?
    var autoOpenWarning: FolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: FolderWatchFileSelectionRequest?

    @ObservationIgnored private(set) var onFolderWatchStarted: ((FolderWatchSession) -> Void)?
    @ObservationIgnored private(set) var onFolderWatchStopped: (() -> Void)?
    @ObservationIgnored private var eventDispatchCoordinator: FolderWatchEventDispatchCoordinator

    let folderWatchDependencies: FolderWatchDependencies

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    init(folderWatchDependencies: FolderWatchDependencies) {
        self.folderWatchDependencies = folderWatchDependencies
        self.eventDispatchCoordinator = FolderWatchEventDispatchCoordinator()
    }

    func setSession(_ session: FolderWatchSession?) {
        activeFolderWatchSession = session
    }

    func setStateCallbacks(
        onStarted: ((FolderWatchSession) -> Void)?,
        onStopped: (() -> Void)?
    ) {
        onFolderWatchStarted = onStarted
        onFolderWatchStopped = onStopped
    }

    func setAdditionalOpenHandler(
        _ handler: @escaping (FolderWatchChangeEvent, FolderWatchSession?, OpenOrigin) -> Void
    ) {
        eventDispatchCoordinator.setAdditionalOpenHandler(handler)
    }

    func dismissAutoOpenWarning() {
        autoOpenWarning = nil
    }

    func handleObservedWatchedFolderChanges(
        _ markdownFileEvents: [FolderWatchChangeEvent],
        currentDocumentFileURL: URL?,
        openPrimary: @escaping (FolderWatchChangeEvent, FolderWatchSession, OpenOrigin) -> Void
    ) {
        guard let session = activeFolderWatchSession else { return }
        lastWatchedFolderEventAt = .now

        let livePlan = folderWatchDependencies.autoOpenPlanner.livePlan(
            for: markdownFileEvents,
            activeSession: session,
            currentDocumentFileURL: currentDocumentFileURL
        )

        if let warning = livePlan.warning {
            autoOpenWarning = warning
        }

        eventDispatchCoordinator.dispatchLiveEvents(
            livePlan.autoOpenEvents,
            session: session,
            origin: .folderWatchAutoOpen,
            openPrimary: openPrimary
        )
    }

    func openInitialMarkdownFilesFromWatchedFolder(
        _ markdownFileEvents: [FolderWatchChangeEvent],
        session: FolderWatchSession,
        openPrimary: @escaping (FolderWatchChangeEvent, FolderWatchSession, OpenOrigin) -> Void
    ) {
        eventDispatchCoordinator.dispatchInitialEvents(
            markdownFileEvents,
            session: session,
            openPrimary: openPrimary
        )
    }

    // MARK: - Internal dispatch coordinator

    private struct FolderWatchEventDispatchCoordinator {
        typealias AdditionalOpenHandler = (FolderWatchChangeEvent, FolderWatchSession?, OpenOrigin) -> Void
        typealias PrimaryOpenHandler = (FolderWatchChangeEvent, FolderWatchSession, OpenOrigin) -> Void

        private(set) var additionalOpenHandler: AdditionalOpenHandler?

        mutating func setAdditionalOpenHandler(_ handler: @escaping AdditionalOpenHandler) {
            additionalOpenHandler = handler
        }

        func dispatchLiveEvents(
            _ plannedEvents: [FolderWatchChangeEvent],
            session: FolderWatchSession,
            origin: OpenOrigin,
            openPrimary: PrimaryOpenHandler
        ) {
            guard !plannedEvents.isEmpty else { return }
            if let additionalOpenHandler {
                for event in plannedEvents {
                    additionalOpenHandler(event, session, origin)
                }
                return
            }
            openPrimary(plannedEvents[0], session, origin)
        }

        func dispatchInitialEvents(
            _ events: [FolderWatchChangeEvent],
            session: FolderWatchSession,
            openPrimary: PrimaryOpenHandler
        ) {
            guard let firstEvent = events.first else { return }
            let initialOrigin: OpenOrigin = events.count > 1
                ? .folderWatchInitialBatchAutoOpen
                : .folderWatchAutoOpen
            openPrimary(firstEvent, session, initialOrigin)
            guard let additionalOpenHandler else { return }
            for event in events.dropFirst() {
                additionalOpenHandler(event, session, .folderWatchInitialBatchAutoOpen)
            }
        }
    }
}
