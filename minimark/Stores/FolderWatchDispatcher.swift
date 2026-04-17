import Foundation
import Observation

@MainActor
@Observable
final class FolderWatchDispatcher {
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    var lastWatchedFolderEventAt: Date?
    var autoOpenWarning: FolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?

    @ObservationIgnored private(set) var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)?
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

    func setSession(_ session: ReaderFolderWatchSession?) {
        activeFolderWatchSession = session
    }

    func setStateCallbacks(
        onStarted: ((ReaderFolderWatchSession) -> Void)?,
        onStopped: (() -> Void)?
    ) {
        onFolderWatchStarted = onStarted
        onFolderWatchStopped = onStopped
    }

    func setAdditionalOpenHandler(
        _ handler: @escaping (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession?, ReaderOpenOrigin) -> Void
    ) {
        eventDispatchCoordinator.setAdditionalOpenHandler(handler)
    }

    func dismissAutoOpenWarning() {
        autoOpenWarning = nil
    }

    func handleObservedWatchedFolderChanges(
        _ markdownFileEvents: [ReaderFolderWatchChangeEvent],
        currentDocumentFileURL: URL?,
        openPrimary: @escaping (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession, ReaderOpenOrigin) -> Void
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
        _ markdownFileEvents: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession,
        openPrimary: @escaping (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession, ReaderOpenOrigin) -> Void
    ) {
        eventDispatchCoordinator.dispatchInitialEvents(
            markdownFileEvents,
            session: session,
            openPrimary: openPrimary
        )
    }

    // MARK: - Internal dispatch coordinator (absorbed from ReaderFolderWatchEventDispatchCoordinator)

    private struct FolderWatchEventDispatchCoordinator {
        typealias AdditionalOpenHandler = (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession?, ReaderOpenOrigin) -> Void
        typealias PrimaryOpenHandler = (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession, ReaderOpenOrigin) -> Void

        private(set) var additionalOpenHandler: AdditionalOpenHandler?

        mutating func setAdditionalOpenHandler(_ handler: @escaping AdditionalOpenHandler) {
            additionalOpenHandler = handler
        }

        func dispatchLiveEvents(
            _ plannedEvents: [ReaderFolderWatchChangeEvent],
            session: ReaderFolderWatchSession,
            origin: ReaderOpenOrigin,
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
            _ events: [ReaderFolderWatchChangeEvent],
            session: ReaderFolderWatchSession,
            openPrimary: PrimaryOpenHandler
        ) {
            guard let firstEvent = events.first else { return }
            let initialOrigin: ReaderOpenOrigin = events.count > 1
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
