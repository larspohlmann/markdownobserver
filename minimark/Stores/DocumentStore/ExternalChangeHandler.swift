import Foundation

@MainActor
final class ExternalChangeHandler {
    private let document: DocumentController
    private let sourceEditingController: SourceEditingController
    private let externalChange: ExternalChangeController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let folderWatch: FolderWatchDependencies
    private let settingsStore: SettingsReading
    private let diffBaselineTracker: DiffBaselineTracking
    private let fileLoader: MarkdownFileLoader
    private let persister: SourceDraftPersister
    private let reloader: DocumentReloader

    init(
        document: DocumentController,
        sourceEditingController: SourceEditingController,
        externalChange: ExternalChangeController,
        folderWatchDispatcher: FolderWatchDispatcher,
        folderWatch: FolderWatchDependencies,
        settingsStore: SettingsReading,
        diffBaselineTracker: DiffBaselineTracking,
        fileLoader: MarkdownFileLoader,
        persister: SourceDraftPersister,
        reloader: DocumentReloader
    ) {
        self.document = document
        self.sourceEditingController = sourceEditingController
        self.externalChange = externalChange
        self.folderWatchDispatcher = folderWatchDispatcher
        self.folderWatch = folderWatch
        self.settingsStore = settingsStore
        self.diffBaselineTracker = diffBaselineTracker
        self.fileLoader = fileLoader
        self.persister = persister
        self.reloader = reloader
    }

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
        reloader.reload(
            at: fileURL,
            diffBaselineMarkdown: baseline,
            acknowledgeExternalChange: false
        )
    }

    func handleObservedFileChange() {
        if let fileURL = document.fileURL,
           folderWatch.settler.handleChangeIfNeeded(
               fileURL: fileURL,
               loader: { [fileLoader, folderWatchDispatcher] url in
                   try fileLoader.load(
                       at: url,
                       folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
                   )
               }
           ) {
            return
        }

        if persister.handlePendingSavedDraftChangeIfNeeded() {
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
            reloader.reload(
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
        return FileRouting.normalizedFileURL(fileURL)
    }

    private var watchedFolderURLForCurrentFile: URL? {
        guard let activeFolderWatchSession = folderWatchDispatcher.activeFolderWatchSession,
              let fileURL = fileURLForCurrentDocument else {
            return nil
        }

        let normalizedWatchedFolderURL = FileRouting.normalizedFileURL(activeFolderWatchSession.folderURL)
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
