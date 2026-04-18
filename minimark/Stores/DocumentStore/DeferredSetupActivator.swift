import Foundation
import Combine

@MainActor
final class DeferredSetupActivator {
    private let document: DocumentController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let folderWatch: FolderWatchDependencies
    private let settingsStore: SettingsReading
    private let diffBaselineTracker: DiffBaselineTracking
    private let fileLoader: MarkdownFileLoader
    private let presenter: DocumentPresenter

    private var hasActivated = false
    private var settingsCancellable: AnyCancellable?

    init(
        document: DocumentController,
        folderWatchDispatcher: FolderWatchDispatcher,
        folderWatch: FolderWatchDependencies,
        settingsStore: SettingsReading,
        diffBaselineTracker: DiffBaselineTracking,
        fileLoader: MarkdownFileLoader,
        presenter: DocumentPresenter
    ) {
        self.document = document
        self.folderWatchDispatcher = folderWatchDispatcher
        self.folderWatch = folderWatch
        self.settingsStore = settingsStore
        self.diffBaselineTracker = diffBaselineTracker
        self.fileLoader = fileLoader
        self.presenter = presenter
    }

    func activateIfNeeded() {
        guard !hasActivated else { return }
        hasActivated = true

        settingsCancellable = settingsStore.settingsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let lookbackInterval = settings.diffBaselineLookback.timeInterval
                if lookbackInterval != self.diffBaselineTracker.currentMinimumAge {
                    self.diffBaselineTracker.updateMinimumAge(lookbackInterval)
                    self.folderWatch.autoOpenPlanner.updateMinimumDiffBaselineAge(lookbackInterval)
                }
            }

        folderWatch.settler.configure(
            currentFileURL: { [weak document] in document?.fileURL },
            loadFile: { [fileLoader, folderWatchDispatcher] url in
                try fileLoader.load(
                    at: url,
                    folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
                )
            },
            onDocumentSettled: { [weak presenter, weak document] loaded, fileURL, diffBaselineMarkdown in
                guard let presenter, let document else { return }
                do {
                    try presenter.presentLoaded(
                        loaded,
                        at: fileURL,
                        diffBaselineMarkdown: diffBaselineMarkdown,
                        resetDocumentViewMode: false,
                        acknowledgeExternalChange: true
                    )
                } catch {
                    document.handle(error)
                }
            },
            onLoadStateChanged: { [weak document] state in
                document?.documentLoadState = state
            }
        )
    }
}
