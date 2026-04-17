import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ReaderStore {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderStore"
    )

    // MARK: - State controllers

    let document: ReaderDocumentController
    let toc = ReaderTOCController()
    let externalChange = ReaderExternalChangeController()
    let sourceEditingController = ReaderSourceEditingController()
    let folderWatchDispatcher: FolderWatchDispatcher
    let renderingController: ReaderRenderingController
    let diffBaselineTracker: DiffBaselineTracking

    // MARK: - Dependencies (exposed for wiring + logging + tests)

    let rendering: ReaderRenderingDependencies
    let file: ReaderFileDependencies
    let folderWatch: FolderWatchDependencies
    let settingsStore: ReaderSettingsReading & ReaderRecentWriting
    let securityScopeResolver: SecurityScopeResolver

    // MARK: - Services

    let fileLoader: MarkdownFileLoader
    let saveLogFormatter: SaveLogFormatter

    // MARK: - Orchestrators

    let presenter: DocumentPresenter
    let postOpenEffects: PostOpenEffects
    let opener: DocumentOpener
    let reloader: DocumentReloader
    let persister: SourceDraftPersister
    let editingFlow: SourceEditingFlow
    let externalChangeHandler: ExternalChangeHandler
    let folderWatchInput: FolderWatchInputHandler
    let setupActivator: DeferredSetupActivator

    // MARK: - Cross-group view-model projections

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

    var onFolderWatchStarted: ((FolderWatchSession) -> Void)? { folderWatchDispatcher.onFolderWatchStarted }
    var onFolderWatchStopped: (() -> Void)? { folderWatchDispatcher.onFolderWatchStopped }

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
        self.reloader = DocumentReloader(
            document: self.document,
            folderWatch: folderWatch,
            presenter: self.presenter,
            onError: { [document = self.document] error in
                document.handle(error)
            }
        )
        self.persister = SourceDraftPersister(
            document: self.document,
            sourceEditingController: self.sourceEditingController,
            externalChange: self.externalChange,
            renderingController: self.renderingController,
            folderWatchDispatcher: folderWatchDispatcher,
            securityScopeResolver: securityScopeResolver,
            fileIO: file.io,
            saveLogFormatter: self.saveLogFormatter
        )
        self.editingFlow = SourceEditingFlow(
            document: self.document,
            sourceEditingController: self.sourceEditingController,
            externalChange: self.externalChange,
            renderingController: self.renderingController,
            folderWatchDispatcher: folderWatchDispatcher,
            persister: self.persister,
            reloader: self.reloader,
            saveLogFormatter: self.saveLogFormatter,
            onError: { [document = self.document] error in
                document.handle(error)
            }
        )
        self.externalChangeHandler = ExternalChangeHandler(
            document: self.document,
            sourceEditingController: self.sourceEditingController,
            externalChange: self.externalChange,
            folderWatchDispatcher: folderWatchDispatcher,
            folderWatch: folderWatch,
            settingsStore: settingsStore,
            diffBaselineTracker: self.diffBaselineTracker,
            fileLoader: self.fileLoader,
            persister: self.persister,
            reloader: self.reloader
        )
        self.folderWatchInput = FolderWatchInputHandler(
            document: self.document,
            folderWatchDispatcher: folderWatchDispatcher,
            opener: self.opener
        )
        self.setupActivator = DeferredSetupActivator(
            document: self.document,
            folderWatchDispatcher: folderWatchDispatcher,
            folderWatch: folderWatch,
            settingsStore: settingsStore,
            diffBaselineTracker: self.diffBaselineTracker,
            fileLoader: self.fileLoader,
            presenter: self.presenter
        )
        self.postOpenEffects.onError = { [document = self.document] error in
            document.handle(error)
        }
        self.postOpenEffects.onObservedFileChange = { [externalChangeHandler = self.externalChangeHandler] in
            externalChangeHandler.handleObservedFileChange()
        }
        self.opener.onActivateDeferredSetupIfNeeded = { [setupActivator = self.setupActivator] in
            setupActivator.activateIfNeeded()
        }
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
