import Foundation

enum ReaderWindowOpenAndWatchFlowSupport {
    static func isSupportedIncomingMarkdownFile(_ url: URL) -> Bool {
        url.isFileURL && ReaderFileRouting.isSupportedMarkdownFileURL(url)
    }

    static func applyInitialSeedIfNeeded(
        seed: ReaderWindowSeed?,
        openDocumentInCurrentWindow: (URL) -> Void,
        openDocumentInSelectedSlot: (URL, ReaderOpenOrigin, ReaderFolderWatchSession?, String?) -> Void,
        resolveRecentOpenedFileURL: (ReaderRecentOpenedFile) -> URL,
        resolveRecentWatchedFolderURL: (ReaderRecentWatchedFolder) -> URL,
        prepareRecentFolderWatch: (URL, ReaderFolderWatchOptions) -> Void
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
        current: (folderURL: URL, options: ReaderFolderWatchOptions)?,
        update: (inout ReaderFolderWatchOptions) -> Void
    ) -> (folderURL: URL, options: ReaderFolderWatchOptions)? {
        guard var current else {
            return nil
        }

        update(&current.options)
        return current
    }
}
