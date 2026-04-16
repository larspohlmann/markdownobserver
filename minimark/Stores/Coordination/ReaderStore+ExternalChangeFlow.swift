import Foundation

extension ReaderStore {
    func refreshFromExternalChange() {
        guard settingsStore.currentSettings.autoRefreshOnExternalChange,
              !sourceEditingController.isSourceEditing,
              let fileURL = document.fileURL else {
            return
        }
        let baseline = diffBaselineTracker.recordAndSelectBaseline(
            markdown: document.sourceMarkdown,
            for: fileURL,
            at: .now
        )
        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: baseline,
            acknowledgeExternalChange: false
        )
    }

    func handleObservedFileChange() {
        if let fileURL = document.fileURL, folderWatch.settler.handleChangeIfNeeded(fileURL: fileURL, loader: { url in try self.loadMarkdownFile(at: url) }) {
            return
        }

        if handlePendingSavedDraftChangeIfNeeded() {
            return
        }

        externalChange.noteObservedExternalChange(kind: .modified)
        if let fileURL = document.fileURL,
           settingsStore.currentSettings.notificationsEnabled {
            folderWatch.systemNotifier.notifyFileChanged(
                fileURL,
                changeKind: currentDocumentHasBeenDeleted ? .deleted : .modified,
                watchedFolderURL: watchedFolderURLForCurrentFile
            )
        }

        if sourceEditingController.isSourceEditing {
            return
        }

        if document.isCurrentFileMissing || currentDocumentHasBeenDeleted {
            reloadCurrentFile(
                at: document.fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: false
            )
            return
        }

        refreshFromExternalChange()
    }

    var fileURLForCurrentDocument: URL? {
        guard let fileURL = document.fileURL else {
            return nil
        }
        return Self.normalizedFileURL(fileURL)
    }

    private var watchedFolderURLForCurrentFile: URL? {
        guard let activeFolderWatchSession = folderWatchDispatcher.activeFolderWatchSession,
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
        guard let fileURL = document.fileURL else {
            return false
        }

        return !FileManager.default.fileExists(atPath: fileURL.path)
    }
}
