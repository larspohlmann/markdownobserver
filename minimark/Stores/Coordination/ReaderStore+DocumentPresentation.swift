import Foundation

extension ReaderStore {

    // MARK: - Document Presentation

    func presentLoadedDocument(
        _ loaded: (markdown: String, modificationDate: Date),
        at fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws {
        try presenter.presentLoaded(
            loaded,
            at: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
    }

    func applyLoadedDocumentState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        presenter.applyLoadedState(
            loaded,
            presentedAs: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode
        )
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        presenter.presentMissing(at: fileURL, error: error)
    }

    func loadAndPresentDocument(
        readURL: URL,
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws -> (markdown: String, modificationDate: Date) {
        try presenter.loadAndPresent(
            readURL: readURL,
            presentedAs: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
    }

    // MARK: - URL Routing

    func handleIncomingOpenURL(_ url: URL) {
        handleIncomingOpenURL(url, origin: .manual)
    }

    func handleIncomingOpenURL(
        _ url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard url.isFileURL else {
            return
        }

        guard Self.isSupportedMarkdownFileURL(url) else {
            return
        }

        let normalizedIncomingURL = Self.normalizedFileURL(url)
        if let fileURL = document.fileURL, Self.normalizedFileURL(fileURL) == normalizedIncomingURL {
            return
        }

        openFile(
            at: normalizedIncomingURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    // MARK: - Post-Open Side Effects

    func applyPostOpenSideEffects(
        accessibleURL: URL,
        normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String
    ) {
        let now = Date()
        folderWatch.settler.beginSettling(
            folderWatch.settler.makePendingContext(
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loadedMarkdown,
                now: now
            )
        )
        if let initialDiffBaselineMarkdown {
            _ = diffBaselineTracker.recordAndSelectBaseline(
                markdown: initialDiffBaselineMarkdown,
                for: normalizedURL,
                at: now
            )
        }
        document.refreshOpenInApplications()
        recordRecentManualOpenIfNeeded(accessibleURL, origin: origin)
        notifyAutoLoadedFileIfNeeded(
            normalizedURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        startWatchingCurrentFile()
    }

    func recordRecentManualOpenIfNeeded(_ accessibleURL: URL, origin: ReaderOpenOrigin) {
        guard origin == .manual else {
            return
        }

        settingsStore.addRecentManuallyOpenedFile(accessibleURL)
    }

    func notifyAutoLoadedFileIfNeeded(
        _ normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?
    ) {
        guard origin.shouldNotifyFileAutoLoaded,
              folderWatchDispatcher.activeFolderWatchSession != nil,
              settingsStore.currentSettings.notificationsEnabled else {
            return
        }

        folderWatch.systemNotifier.notifyFileChanged(
            normalizedURL,
            changeKind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            watchedFolderURL: folderWatchDispatcher.activeFolderWatchSession?.folderURL
        )
    }

    // MARK: - Document Reload

    func reloadCurrentFile(
        forceHighlight: Bool = true,
        acknowledgeExternalChange: Bool = true
    ) {
        guard let fileURL = document.fileURL else {
            return
        }

        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: forceHighlight ? document.sourceMarkdown : nil,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
    }

    func reloadCurrentFile(
        at fileURL: URL?,
        diffBaselineMarkdown: String?,
        acknowledgeExternalChange: Bool
    ) {
        guard let fileURL else {
            return
        }

        do {
            _ = try loadAndPresentDocument(
                readURL: fileURL,
                presentedAs: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                resetDocumentViewMode: false,
                acknowledgeExternalChange: acknowledgeExternalChange
            )
            folderWatch.settler.clearSettling()
        } catch {
            handleDocumentReloadFailure(error, for: fileURL)
        }
    }

    func handleDocumentReloadFailure(_ error: Error, for fileURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            handle(error)
            return
        }

        presentMissingDocument(at: fileURL, error: error)
    }
}
