import Foundation

extension ReaderStore {
    func openFile(at url: URL) {
        openFile(at: url, origin: .manual)
    }

    func openFile(
        at url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        do {
            let accessibleURL = url
            let normalizedURL = Self.normalizedFileURL(accessibleURL)
            fileWatcher.stopWatching()
            activateFileSecurityScope(for: accessibleURL, reason: "open")
            bindFolderWatchSessionIfNeeded(folderWatchSession)
            let readURL = effectiveAccessibleFileURL(for: normalizedURL, reason: "open")
            currentOpenOrigin = origin
            logSaveInfo("opened document for reading: \(saveLogContext(for: normalizedURL))")

            let loaded = try loadAndPresentDocument(
                readURL: readURL,
                presentedAs: normalizedURL,
                diffBaselineMarkdown: initialDiffBaselineMarkdown,
                resetDocumentViewMode: true,
                acknowledgeExternalChange: true
            )
            applyPostOpenSideEffects(
                accessibleURL: accessibleURL,
                normalizedURL: normalizedURL,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loaded.markdown
            )
        } catch {
            handle(error)
        }
    }

    private func applyPostOpenSideEffects(
        accessibleURL: URL,
        normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String
    ) {
        setPendingAutoOpenSettlingContext(
            makePendingAutoOpenSettlingContext(
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loadedMarkdown,
                now: Date()
            )
        )
        refreshOpenInApplications()
        recordRecentManualOpenIfNeeded(accessibleURL, origin: origin)
        notifyAutoLoadedFileIfNeeded(
            normalizedURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        startWatchingCurrentFile()
    }

    private func recordRecentManualOpenIfNeeded(_ accessibleURL: URL, origin: ReaderOpenOrigin) {
        guard origin == .manual else {
            return
        }

        settingsStore.addRecentManuallyOpenedFile(accessibleURL)
    }

    private func notifyAutoLoadedFileIfNeeded(
        _ normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?
    ) {
        guard origin.shouldNotifyFileAutoLoaded,
              activeFolderWatchSession != nil,
              settingsStore.currentSettings.notificationsEnabled else {
            return
        }

        systemNotifier.notifyFileAutoLoaded(
            normalizedURL,
            changeKind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            watchedFolderURL: activeFolderWatchSession?.folderURL
        )
    }

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
}
