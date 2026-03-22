import Foundation

extension ReaderWindowRootView {
    func openIncomingURL(_ url: URL) {
        guard ReaderWindowOpenAndWatchFlowSupport.isSupportedIncomingMarkdownFile(url) else {
            return
        }

        openDocumentInSelectedSlot(at: url, origin: .manual)
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        openDocumentInSelectedSlot(
            at: fileURL,
            origin: .manual,
            folderWatchSession: sharedFolderWatchSession
        )
    }

    func applyInitialSeedIfNeeded() {
        ReaderWindowOpenAndWatchFlowSupport.applyInitialSeedIfNeeded(
            seed: seed,
            openDocumentInCurrentWindow: { fileURL in
                openDocumentInCurrentWindow(fileURL)
            },
            openDocumentInSelectedSlot: { fileURL, origin, folderWatchSession, initialDiffBaselineMarkdown in
                openDocumentInSelectedSlot(
                    at: fileURL,
                    origin: origin,
                    folderWatchSession: folderWatchSession,
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                )
            },
            prepareRecentFolderWatch: { entry in
                prepareRecentFolderWatch(entry)
            }
        )
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        sidebarDocumentController.openDocumentInSelectedSlot(
            at: fileURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        refreshWindowPresentation()
    }

    func prepareFolderWatchOptions(for folderURL: URL) {
        presentFolderWatchOptions(for: folderURL, options: .default)
    }

    func presentFolderWatchOptions(for folderURL: URL, options: ReaderFolderWatchOptions) {
        pendingFolderWatchRequest = PendingFolderWatchRequest(
            folderURL: folderURL,
            options: options
        )
        isFolderWatchOptionsPresented = true
    }

    func prepareRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        presentFolderWatchOptions(for: entry.resolvedFolderURL, options: entry.options)
    }

    func updatePendingFolderWatchRequest(
        _ update: (inout PendingFolderWatchRequest) -> Void
    ) {
        guard var request = pendingFolderWatchRequest else {
            return
        }

        update(&request)
        pendingFolderWatchRequest = request
    }
}
