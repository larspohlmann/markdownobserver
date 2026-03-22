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

struct ReaderSourceEditingTransition {
    let draftMarkdown: String?
    let sourceMarkdown: String
    let sourceEditorSeedMarkdown: String
    let unsavedChangedRegions: [ChangedRegion]
    let isSourceEditing: Bool
    let hasUnsavedDraftChanges: Bool
}

struct ReaderSourceEditingCoordinator {
    func canStart(
        hasOpenDocument: Bool,
        isCurrentFileMissing: Bool,
        isSourceEditing: Bool
    ) -> Bool {
        hasOpenDocument && !isCurrentFileMissing && !isSourceEditing
    }

    func canUpdate(isSourceEditing: Bool) -> Bool {
        isSourceEditing
    }

    func canDiscard(isSourceEditing: Bool) -> Bool {
        isSourceEditing
    }

    func beginSession(markdown: String) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: markdown,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: markdown,
            unsavedChangedRegions: [],
            isSourceEditing: true,
            hasUnsavedDraftChanges: false
        )
    }

    func updateDraft(
        markdown: String,
        sourceEditorSeedMarkdown: String,
        diffBaselineMarkdown: String,
        unsavedChangedRegions: [ChangedRegion]
    ) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: markdown,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: sourceEditorSeedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions,
            isSourceEditing: true,
            hasUnsavedDraftChanges: markdown != diffBaselineMarkdown
        )
    }

    func finishSession(markdown: String) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: nil,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: markdown,
            unsavedChangedRegions: [],
            isSourceEditing: false,
            hasUnsavedDraftChanges: false
        )
    }
}
