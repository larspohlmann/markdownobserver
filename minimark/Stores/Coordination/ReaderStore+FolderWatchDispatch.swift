import Foundation

extension ReaderStore {
    func handleObservedWatchedFolderChanges(_ markdownFileEvents: [FolderWatchChangeEvent]) {
        folderWatchDispatcher.handleObservedWatchedFolderChanges(
            markdownFileEvents,
            currentDocumentFileURL: fileURLForCurrentDocument
        ) { [self] event, session, origin in
            openFile(
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
        ) { [self] event, eventSession, eventOrigin in
            openFile(
                at: event.fileURL,
                origin: eventOrigin,
                folderWatchSession: eventSession,
                initialDiffBaselineMarkdown: event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }
}
