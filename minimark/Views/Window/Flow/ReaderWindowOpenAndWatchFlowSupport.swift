import Foundation

enum ReaderWindowOpenAndWatchFlowSupport {
    static func isSupportedIncomingMarkdownFile(_ url: URL) -> Bool {
        url.isFileURL && FileRouting.isSupportedMarkdownFileURL(url)
    }

    static func applyInitialSeedIfNeeded(
        seed: WindowSeed?,
        openDocumentInCurrentWindow: (URL) -> Void,
        openDocumentInSelectedSlot: (URL, OpenOrigin, FolderWatchSession?, String?) -> Void,
        resolveRecentOpenedFileURL: (RecentOpenedFile) -> URL,
        resolveRecentWatchedFolderURL: (RecentWatchedFolder) -> URL,
        prepareRecentFolderWatch: (URL, FolderWatchOptions) -> Void
    ) {
        if let recentOpenedFile = seed?.recentOpenedFile {
            openDocumentInCurrentWindow(resolveRecentOpenedFileURL(recentOpenedFile))
        } else if let fileURL = seed?.fileURL {
            openDocumentInSelectedSlot(
                fileURL,
                seed?.openOrigin ?? .manual,
                seed?.folderWatchSession,
                seed?.initialDiffBaselineMarkdown
            )
        }

        if let recentWatchedFolder = seed?.recentWatchedFolder {
            let resolvedFolderURL = resolveRecentWatchedFolderURL(recentWatchedFolder)
            prepareRecentFolderWatch(resolvedFolderURL, recentWatchedFolder.options)
        }
    }

    static func updatedPendingFolderWatchRequest(
        current: (folderURL: URL, options: FolderWatchOptions)?,
        update: (inout FolderWatchOptions) -> Void
    ) -> (folderURL: URL, options: FolderWatchOptions)? {
        guard var current else {
            return nil
        }

        update(&current.options)
        return current
    }
}
