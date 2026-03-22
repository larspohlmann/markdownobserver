import Foundation

extension ReaderStore {
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

    func refreshFromExternalChange() {
        guard settingsStore.currentSettings.autoRefreshOnExternalChange,
              !isSourceEditing else {
            return
        }
        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: sourceMarkdown,
            acknowledgeExternalChange: false
        )
    }

    func handleObservedFileChange() {
        if handlePendingAutoOpenSettlingChangeIfNeeded() {
            return
        }

        if handlePendingSavedDraftChangeIfNeeded() {
            return
        }

        noteObservedExternalChange()
        if let fileURL,
           settingsStore.currentSettings.notificationsEnabled {
            systemNotifier.notifyExternalChange(
                for: fileURL,
                autoRefreshed: settingsStore.currentSettings.autoRefreshOnExternalChange,
                watchedFolderURL: watchedFolderURLForCurrentFile
            )
        }

        if isSourceEditing {
            return
        }

        if isCurrentFileMissing || currentDocumentHasBeenDeleted {
            reloadCurrentFile(
                at: fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: false
            )
            return
        }

        refreshFromExternalChange()
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
            clearPendingAutoOpenSettling()
        } catch {
            handleDocumentReloadFailure(error, for: fileURL)
        }
    }

    var fileURLForCurrentDocument: URL? {
        guard let fileURL else {
            return nil
        }
        return Self.normalizedFileURL(fileURL)
    }

    private var watchedFolderURLForCurrentFile: URL? {
        guard let activeFolderWatchSession,
              let fileURL = fileURLForCurrentDocument else {
            return nil
        }

        let normalizedWatchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
        switch activeFolderWatchSession.options.scope {
        case .selectedFolderOnly:
            return fileURL.deletingLastPathComponent().path == normalizedWatchedFolderURL.path
                ? normalizedWatchedFolderURL
                : nil
        case .includeSubfolders:
            let folderPath = normalizedWatchedFolderURL.path.hasSuffix("/")
                ? normalizedWatchedFolderURL.path
                : normalizedWatchedFolderURL.path + "/"
            return fileURL.path.hasPrefix(folderPath) ? normalizedWatchedFolderURL : nil
        }
    }

    private var currentDocumentHasBeenDeleted: Bool {
        guard let fileURL else {
            return false
        }

        return !FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func handleDocumentReloadFailure(_ error: Error, for fileURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            handle(error)
            return
        }

        presentMissingDocument(at: fileURL, error: error)
    }
}
