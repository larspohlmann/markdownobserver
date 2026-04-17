import Foundation

@MainActor
final class PostOpenEffects {
    private let document: DocumentController
    private let settingsStore: SettingsReading & RecentWriting
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let folderWatch: FolderWatchDependencies
    private let diffBaselineTracker: DiffBaselineTracking
    private let fileWatcher: FileChangeWatching
    var onError: (@MainActor (Error) -> Void)?
    var onObservedFileChange: (@MainActor () -> Void)?

    init(
        document: DocumentController,
        settingsStore: SettingsReading & RecentWriting,
        folderWatchDispatcher: FolderWatchDispatcher,
        folderWatch: FolderWatchDependencies,
        diffBaselineTracker: DiffBaselineTracking,
        fileWatcher: FileChangeWatching
    ) {
        self.document = document
        self.settingsStore = settingsStore
        self.folderWatchDispatcher = folderWatchDispatcher
        self.folderWatch = folderWatch
        self.diffBaselineTracker = diffBaselineTracker
        self.fileWatcher = fileWatcher
    }

    func apply(
        accessibleURL: URL,
        normalizedURL: URL,
        origin: OpenOrigin,
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

    func startWatchingCurrentFile() {
        guard let fileURL = document.fileURL else {
            return
        }

        do {
            try fileWatcher.startWatching(fileURL: fileURL) { [weak self] in
                Task { @MainActor in
                    self?.onObservedFileChange?()
                }
            }
        } catch {
            onError?(error)
        }
    }

    private func recordRecentManualOpenIfNeeded(_ accessibleURL: URL, origin: OpenOrigin) {
        guard origin == .manual else {
            return
        }
        settingsStore.addRecentManuallyOpenedFile(accessibleURL)
    }

    private func notifyAutoLoadedFileIfNeeded(
        _ normalizedURL: URL,
        origin: OpenOrigin,
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
}
