import Foundation

extension ReaderWindowRootView {
    func openIncomingURL(_ url: URL) {
        guard ReaderWindowOpenAndWatchFlowSupport.isSupportedIncomingMarkdownFile(url) else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [url],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))
        applyWindowTitlePresentation()
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [fileURL],
            origin: .manual,
            folderWatchSession: sharedFolderWatchSession,
            slotStrategy: .replaceSelectedSlot
        ))
        applyWindowTitlePresentation()
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
            resolveRecentOpenedFileURL: { entry in
                settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
            },
            resolveRecentWatchedFolderURL: { entry in
                settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
            },
            prepareRecentFolderWatch: { folderURL, options in
                presentFolderWatchOptions(for: folderURL, options: options)
            }
        )
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedURL],
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedURL: $0] } ?? [:],
            slotStrategy: .replaceSelectedSlot
        ))
        applyWindowTitlePresentation()
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
        let resolvedFolderURL = settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
        presentFolderWatchOptions(for: resolvedFolderURL, options: entry.options)
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
