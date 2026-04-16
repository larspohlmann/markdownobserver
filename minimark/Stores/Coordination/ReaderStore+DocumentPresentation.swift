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
        cancelPendingDraftPreviewRender()
        applyLoadedDocumentState(
            loaded,
            presentedAs: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode
        )
        try renderCurrentMarkdownImmediately()
        if acknowledgeExternalChange {
            externalChange.clear()
        }
        identity.isCurrentFileMissing = false
        identity.lastError = nil
    }

    func applyLoadedDocumentState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        identity.fileURL = fileURL
        identity.fileDisplayName = fileURL.lastPathComponent
        content.savedMarkdown = loaded.markdown
        editing.draftMarkdown = nil
        editing.pendingSavedDraftDiffBaselineMarkdown = nil
        content.sourceMarkdown = loaded.markdown
        editing.sourceEditorSeedMarkdown = loaded.markdown
        content.fileLastModifiedAt = loaded.modificationDate

        if resetDocumentViewMode {
            editing.documentViewMode = .preview
        }

        content.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        editing.unsavedChangedRegions = []
        editing.isSourceEditing = false
        editing.hasUnsavedDraftChanges = false
        toc.clear()
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        identity.fileURL = fileURL
        identity.fileDisplayName = fileURL.lastPathComponent
        content.fileLastModifiedAt = nil
        identity.openInApplications = []
        identity.isCurrentFileMissing = true
        identity.lastError = ReaderPresentableError(from: error)
        folderWatch.settler.clearSettling()
    }

    func loadAndPresentDocument(
        readURL: URL,
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws -> (markdown: String, modificationDate: Date) {
        let loaded = try loadMarkdownFile(at: readURL)
        try presentLoadedDocument(
            loaded,
            at: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
        return loaded
    }

    // MARK: - URL Routing

    func handleIncomingOpenURL(_ url: URL) {
        handleIncomingOpenURL(url, origin: .manual)
    }

    func handleIncomingOpenURL(
        _ url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard url.isFileURL else {
            return
        }

        guard Self.isSupportedMarkdownFileURL(url) else {
            return
        }

        let normalizedIncomingURL = Self.normalizedFileURL(url)
        if let fileURL, Self.normalizedFileURL(fileURL) == normalizedIncomingURL {
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
        refreshOpenInApplications()
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
              activeFolderWatchSession != nil,
              settingsStore.currentSettings.notificationsEnabled else {
            return
        }

        folderWatch.systemNotifier.notifyFileChanged(
            normalizedURL,
            changeKind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            watchedFolderURL: activeFolderWatchSession?.folderURL
        )
    }

    // MARK: - Document Reload

    func reloadCurrentFile(
        forceHighlight: Bool = true,
        acknowledgeExternalChange: Bool = true
    ) {
        guard let fileURL else {
            return
        }

        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: forceHighlight ? sourceMarkdown : nil,
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
