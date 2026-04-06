import Foundation

struct ReaderFolderWatchEventDispatchCoordinator {
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
        guard !plannedEvents.isEmpty else {
            return
        }

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
        guard let firstEvent = events.first else {
            return
        }

        let initialOrigin: ReaderOpenOrigin = events.count > 1
            ? .folderWatchInitialBatchAutoOpen
            : .folderWatchAutoOpen

        openPrimary(firstEvent, session, initialOrigin)

        guard let additionalOpenHandler else {
            return
        }

        for event in events.dropFirst() {
            additionalOpenHandler(event, session, .folderWatchInitialBatchAutoOpen)
        }
    }
}
