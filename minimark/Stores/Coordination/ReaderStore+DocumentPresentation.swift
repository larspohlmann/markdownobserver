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
        postOpenEffects.apply(
            accessibleURL: accessibleURL,
            normalizedURL: normalizedURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
            loadedMarkdown: loadedMarkdown
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
