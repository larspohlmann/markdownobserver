import Foundation
import Combine
import Observation
import OSLog

@MainActor
@Observable
final class ReaderStore {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderStore"
    )

    let document: ReaderDocumentController

    // MARK: - Cross-group computed properties

    var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let date = externalChange.lastExternalChangeAt { return .updated(date) }
        if let date = document.fileLastModifiedAt { return .lastModified(date) }
        if let date = renderingController.lastRefreshAt { return .updated(date) }
        return nil
    }

    var decoratedWindowTitle: String {
        (externalChange.hasUnacknowledgedExternalChange || sourceEditingController.hasUnsavedDraftChanges)
            ? "* \(document.windowTitle)" : document.windowTitle
    }

    let toc = ReaderTOCController()

    let externalChange = ReaderExternalChangeController()
    let sourceEditingController = ReaderSourceEditingController()
    let folderWatchDispatcher: FolderWatchDispatcher
    let rendering: ReaderRenderingDependencies
    let renderingController: ReaderRenderingController
    let file: ReaderFileDependencies
    let folderWatch: FolderWatchDependencies
    let settingsStore: ReaderSettingsReading & ReaderRecentWriting
    let securityScopeResolver: SecurityScopeResolver
    let fileLoader: MarkdownFileLoader
    let saveLogFormatter: SaveLogFormatter
    let presenter: DocumentPresenter
    let postOpenEffects: PostOpenEffects
    let opener: DocumentOpener
    @ObservationIgnored private var settingsCancellable: AnyCancellable?

    // MARK: - Internal: accessible to Coordination extensions
    // These properties exist for coordination extensions in Stores/Coordination/.
    // They must be at least `internal` because Swift extensions in separate files
    // cannot see `private` members.  Do not access them from views or other stores.
    //
    // - diffBaselineTracker: read-only (`let`) — used by ExternalChangeFlow
    // - onFolderWatchStarted/Stopped: read-only from extensions (called, never reassigned);
    //   set exclusively through folderWatchDispatcher.setStateCallbacks(onStarted:onStopped:)
    let diffBaselineTracker: DiffBaselineTracking

    var onFolderWatchStarted: ((FolderWatchSession) -> Void)? { folderWatchDispatcher.onFolderWatchStarted }
    var onFolderWatchStopped: (() -> Void)? { folderWatchDispatcher.onFolderWatchStopped }

    @ObservationIgnored private var hasActivatedDeferredSetup = false

    init(
        rendering: ReaderRenderingDependencies,
        file: ReaderFileDependencies,
        folderWatch: FolderWatchDependencies,
        settingsStore: ReaderSettingsReading & ReaderRecentWriting,
        securityScopeResolver: SecurityScopeResolver,
        diffBaselineTracker: DiffBaselineTracking? = nil
    ) {
        self.document = ReaderDocumentController(
            fileDependencies: file,
            settingsStore: settingsStore,
            settler: folderWatch.settler
        )
        let folderWatchDispatcher = FolderWatchDispatcher(folderWatchDependencies: folderWatch)
        self.folderWatchDispatcher = folderWatchDispatcher
        self.rendering = rendering
        self.renderingController = ReaderRenderingController(
            renderingDependencies: rendering,
            settingsStore: settingsStore,
            securityScopeResolver: securityScopeResolver
        )
        self.file = file
        self.folderWatch = folderWatch
        self.settingsStore = settingsStore
        self.securityScopeResolver = securityScopeResolver
        self.diffBaselineTracker = diffBaselineTracker ?? DiffBaselineTracker(
            minimumAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
        )
        self.fileLoader = MarkdownFileLoader(
            securityScopeResolver: securityScopeResolver,
            fileIO: file.io
        )
        self.saveLogFormatter = SaveLogFormatter(
            securityScopeResolver: securityScopeResolver,
            document: self.document,
            sourceEditingController: self.sourceEditingController,
            folderWatchDispatcher: folderWatchDispatcher
        )
        self.presenter = DocumentPresenter(
            document: self.document,
            sourceEditingController: self.sourceEditingController,
            externalChange: self.externalChange,
            toc: self.toc,
            renderingController: self.renderingController,
            folderWatchDispatcher: folderWatchDispatcher,
            settler: folderWatch.settler,
            fileLoader: self.fileLoader
        )
        self.postOpenEffects = PostOpenEffects(
            document: self.document,
            settingsStore: settingsStore,
            folderWatchDispatcher: folderWatchDispatcher,
            folderWatch: folderWatch,
            diffBaselineTracker: self.diffBaselineTracker,
            fileWatcher: file.watcher
        )
        self.opener = DocumentOpener(
            document: self.document,
            externalChange: self.externalChange,
            sourceEditingController: self.sourceEditingController,
            folderWatchDispatcher: folderWatchDispatcher,
            securityScopeResolver: securityScopeResolver,
            folderWatch: folderWatch,
            fileWatcher: file.watcher,
            fileLoader: self.fileLoader,
            presenter: self.presenter,
            postOpenEffects: self.postOpenEffects,
            onError: { [document = self.document] error in
                document.handle(error)
            }
        )
        self.postOpenEffects.onError = { [document = self.document] error in
            document.handle(error)
        }
        self.postOpenEffects.onObservedFileChange = { [weak self] in
            self?.handleObservedFileChange()
        }
        self.opener.onActivateDeferredSetupIfNeeded = { [weak self] in
            self?.activateDeferredSetupIfNeeded()
        }
    }

    func activateDeferredSetupIfNeeded() {
        guard !hasActivatedDeferredSetup else { return }
        hasActivatedDeferredSetup = true

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
            currentFileURL: { [weak self] in self?.document.fileURL },
            loadFile: { [weak self] url in
                guard let self else { throw ReaderError.noOpenFileInReader }
                return try self.loadMarkdownFile(at: url)
            },
            onDocumentSettled: { [weak self] loaded, fileURL, diffBaselineMarkdown in
                guard let self else { return }
                do {
                    try self.presentLoadedDocument(
                        loaded,
                        at: fileURL,
                        diffBaselineMarkdown: diffBaselineMarkdown,
                        resetDocumentViewMode: false,
                        acknowledgeExternalChange: true
                    )
                } catch {
                    self.handle(error)
                }
            },
            onLoadStateChanged: { [weak self] state in
                self?.document.documentLoadState = state
            }
        )
    }

    func clearOpenDocument() {
        // Note: diffBaselineTracker is intentionally NOT reset here.
        // Per-file-URL history is preserved across open/close cycles
        // so the lookback window remains time-based, not session-based.
        securityScopeResolver.endFileAndDirectoryAccess()

        document.clearOpenDocument()
        renderingController.reset()
        sourceEditingController.reset()
        externalChange.clear()
        toc.clear()
    }

    func presentError(_ error: Error) {
        handle(error)
    }

    func startWatchingCurrentFile() {
        postOpenEffects.startWatchingCurrentFile()
    }


    func handle(_ error: Error) {
        document.handle(error)
    }

    static func normalizedFileURL(_ url: URL) -> URL {
        ReaderFileRouting.normalizedFileURL(url)
    }

    static func isSupportedMarkdownFileURL(_ url: URL) -> Bool {
        ReaderFileRouting.isSupportedMarkdownFileURL(url)
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testSetFileURL(_ url: URL?) { document.fileURL = url }
    func testSetFileDisplayName(_ name: String) { document.fileDisplayName = name }
    func testSetFileLastModifiedAt(_ date: Date?) { document.fileLastModifiedAt = date }
    func testSetHasUnacknowledgedExternalChange(_ value: Bool) { externalChange.hasUnacknowledgedExternalChange = value }
    func testSetIsCurrentFileMissing(_ value: Bool) { document.isCurrentFileMissing = value }
    #endif
}
