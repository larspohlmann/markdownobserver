import Foundation

@MainActor
final class FolderWatchInputHandler {
    private let document: DocumentController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let opener: DocumentOpener

    init(
        document: DocumentController,
        folderWatchDispatcher: FolderWatchDispatcher,
        opener: DocumentOpener
    ) {
        self.document = document
        self.folderWatchDispatcher = folderWatchDispatcher
        self.opener = opener
    }

    func handleObservedWatchedFolderChanges(_ markdownFileEvents: [FolderWatchChangeEvent]) {
        folderWatchDispatcher.handleObservedWatchedFolderChanges(
            markdownFileEvents,
            currentDocumentFileURL: document.fileURL.map { FileRouting.normalizedFileURL($0) }
        ) { [opener] event, session, origin in
            opener.open(
                at: event.fileURL,
                origin: origin,
                folderWatchSession: session,
                initialDiffBaselineMarkdown: event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }

    func openInitialMarkdownFilesFromWatchedFolder(
        _ markdownFileEvents: [FolderWatchChangeEvent],
        session: FolderWatchSession
    ) {
        folderWatchDispatcher.openInitialMarkdownFilesFromWatchedFolder(
            markdownFileEvents,
            session: session
        ) { [opener] event, eventSession, eventOrigin in
            opener.open(
                at: event.fileURL,
                origin: eventOrigin,
                folderWatchSession: eventSession,
                initialDiffBaselineMarkdown: event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }
}
