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
    var activeFolderWatchSession: ReaderFolderWatchSession? { folderWatchDispatcher.activeFolderWatchSession }
    var lastWatchedFolderEventAt: Date? {
        get { folderWatchDispatcher.lastWatchedFolderEventAt }
        set { folderWatchDispatcher.lastWatchedFolderEventAt = newValue }
    }
    var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning? {
        get { folderWatchDispatcher.autoOpenWarning }
        set { folderWatchDispatcher.autoOpenWarning = newValue }
    }
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest? {
        get { folderWatchDispatcher.pendingFileSelectionRequest }
        set { folderWatchDispatcher.pendingFileSelectionRequest = newValue }
    }

    // MARK: - Document forwarding

    var fileURL: URL? { document.fileURL }
    var fileDisplayName: String { document.fileDisplayName }
    var documentLoadState: ReaderDocumentLoadState { document.documentLoadState }
    var isCurrentFileMissing: Bool { document.isCurrentFileMissing }
    var lastError: ReaderPresentableError? { document.lastError }
    var openInApplications: [ReaderExternalApplication] { document.openInApplications }
    var needsImageDirectoryAccess: Bool { renderingController.needsImageDirectoryAccess }
    var hasOpenDocument: Bool { document.hasOpenDocument }
    var isDeferredDocument: Bool { document.isDeferredDocument }
    var windowTitle: String { document.windowTitle }
    var sourceMarkdown: String { document.sourceMarkdown }
    var renderedHTMLDocument: String { renderingController.renderedHTMLDocument }
    var changedRegions: [ChangedRegion] { document.changedRegions }
    var lastRefreshAt: Date? { renderingController.lastRefreshAt }
    var lastExternalChangeAt: Date? { externalChange.lastExternalChangeAt }
    var fileLastModifiedAt: Date? { document.fileLastModifiedAt }
    var hasUnacknowledgedExternalChange: Bool { externalChange.hasUnacknowledgedExternalChange }

    // MARK: - Editing forwarding

    var documentViewMode: ReaderDocumentViewMode { sourceEditingController.documentViewMode }
    var sourceEditorSeedMarkdown: String { sourceEditingController.sourceEditorSeedMarkdown }
    var unsavedChangedRegions: [ChangedRegion] { sourceEditingController.unsavedChangedRegions }
    var isSourceEditing: Bool { sourceEditingController.isSourceEditing }
    var hasUnsavedDraftChanges: Bool { sourceEditingController.hasUnsavedDraftChanges }
    var canSaveSourceDraft: Bool { sourceEditingController.canSaveSourceDraft }
    var canDiscardSourceDraft: Bool { sourceEditingController.canDiscardSourceDraft }

    // MARK: - Cross-group computed properties

    var canStartSourceEditing: Bool {
        document.hasOpenDocument && !document.isCurrentFileMissing && !sourceEditingController.isSourceEditing
    }

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

    // MARK: - Table of Contents
    let toc = ReaderTOCController()
    var tocHeadings: [TOCHeading] { toc.headings }
    var isTOCVisible: Bool {
        get { toc.isVisible }
        set { toc.isVisible = newValue }
    }
    var tocScrollRequest: TOCScrollRequest? {
        get { toc.scrollRequest }
        set { toc.scrollRequest = newValue }
    }
    var tocScrollRequestCounter: Int { toc.scrollRequestCounter }

    func updateTOCHeadings(_ headings: [TOCHeading]) { toc.updateHeadings(headings) }
    func toggleTOC() { toc.toggle() }
    func scrollToTOCHeading(_ heading: TOCHeading) { toc.scrollTo(heading) }

    let externalChange = ReaderExternalChangeController()
    let sourceEditingController = ReaderSourceEditingController()
    let folderWatchDispatcher: ReaderFolderWatchDispatcher
    let rendering: ReaderRenderingDependencies
    let renderingController: ReaderRenderingController
    let file: ReaderFileDependencies
    let folderWatch: ReaderFolderWatchDependencies
    let settingsStore: ReaderSettingsStoring
    let securityScopeResolver: SecurityScopeResolver
    let sourceEditingCoordinator = ReaderSourceEditingCoordinator()

    @ObservationIgnored private var settingsCancellable: AnyCancellable?
    var needsAppearanceRender: Bool {
        get { renderingController.needsAppearanceRender }
        set { renderingController.needsAppearanceRender = newValue }
    }

    // MARK: - Internal: accessible to Coordination extensions
    // These properties exist for coordination extensions in Stores/Coordination/.
    // They must be at least `internal` because Swift extensions in separate files
    // cannot see `private` members.  Do not access them from views or other stores.
    //
    // - diffBaselineTracker: read-only (`let`) — used by ExternalChangeFlow
    // - onFolderWatchStarted/Stopped: read-only from extensions (called, never reassigned);
    //   set exclusively through setFolderWatchStateCallbacks(_:onStopped:)
    let diffBaselineTracker: DiffBaselineTracking

    var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)? { folderWatchDispatcher.onFolderWatchStarted }
    var onFolderWatchStopped: (() -> Void)? { folderWatchDispatcher.onFolderWatchStopped }

    @ObservationIgnored private var hasActivatedDeferredSetup = false

    init(
        rendering: ReaderRenderingDependencies,
        file: ReaderFileDependencies,
        folderWatch: ReaderFolderWatchDependencies,
        settingsStore: ReaderSettingsStoring,
        securityScopeResolver: SecurityScopeResolver,
        diffBaselineTracker: DiffBaselineTracking? = nil
    ) {
        self.document = ReaderDocumentController(
            fileDependencies: file,
            settingsStore: settingsStore,
            settler: folderWatch.settler
        )
        self.folderWatchDispatcher = ReaderFolderWatchDispatcher(folderWatchDependencies: folderWatch)
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
            currentFileURL: { [weak self] in self?.fileURL },
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

    var isWatchingFolder: Bool {
        folderWatchDispatcher.isWatchingFolder
    }

    var currentSettings: ReaderSettings {
        settingsStore.currentSettings
    }

    func setOpenAdditionalDocumentForFolderWatchEventHandler(
        _ handler: @escaping (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession?, ReaderOpenOrigin) -> Void
    ) {
        folderWatchDispatcher.setAdditionalOpenHandler(handler)
    }

    func setDocumentViewMode(_ mode: ReaderDocumentViewMode) {
        sourceEditingController.setViewMode(mode, hasOpenDocument: hasOpenDocument)
    }

    func toggleDocumentViewMode() {
        sourceEditingController.toggleViewMode()
    }

    func setFolderWatchStateCallbacks(
        onStarted: ((ReaderFolderWatchSession) -> Void)?,
        onStopped: (() -> Void)?
    ) {
        folderWatchDispatcher.setStateCallbacks(onStarted: onStarted, onStopped: onStopped)
    }

    func setActiveFolderWatchSession(_ session: ReaderFolderWatchSession?) {
        folderWatchDispatcher.setSession(session)
    }

    func setLastWatchedFolderEventAt(_ date: Date?) {
        folderWatchDispatcher.lastWatchedFolderEventAt = date
    }

    func setFolderWatchAutoOpenWarning(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchDispatcher.autoOpenWarning = warning
    }

    func noteObservedExternalChange(kind: ReaderExternalChangeKind = .modified) {
        externalChange.noteObservedExternalChange(kind: kind)
    }

    func clearExternalChangeIndicator() {
        externalChange.clear()
    }

    func deferFile(at url: URL, origin: ReaderOpenOrigin = .folderWatchInitialBatchAutoOpen, folderWatchSession: ReaderFolderWatchSession?) {
        document.deferFile(at: url, origin: origin)
        if let folderWatchSession {
            folderWatchDispatcher.setSession(folderWatchSession)
        }
    }

    func transitionToLoading() {
        document.transitionToLoading()
    }

    func clearLoadingState() {
        document.clearLoadingState()
    }

    func holdLoadingOverlayBriefly() {
        document.holdLoadingOverlayBriefly()
    }

    func clearOpenDocument() {
        renderingController.cancelPendingDraftPreviewRender()
        // Note: diffBaselineTracker is intentionally NOT reset here.
        // Per-file-URL history is preserved across open/close cycles
        // so the lookback window remains time-based, not session-based.
        securityScopeResolver.endFileAndDirectoryAccess()

        document.clearOpenDocument()
        sourceEditingController.reset()
        toc.clear()
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchDispatcher.dismissAutoOpenWarning()
    }

    func applySourceEditingTransition(_ transition: ReaderSourceEditingTransition) {
        sourceEditingController.draftMarkdown = transition.draftMarkdown
        document.sourceMarkdown = transition.sourceMarkdown
        sourceEditingController.sourceEditorSeedMarkdown = transition.sourceEditorSeedMarkdown
        sourceEditingController.unsavedChangedRegions = transition.unsavedChangedRegions
        sourceEditingController.isSourceEditing = transition.isSourceEditing
        sourceEditingController.hasUnsavedDraftChanges = transition.hasUnsavedDraftChanges
    }

    func refreshOpenInApplications() {
        document.refreshOpenInApplications()
    }

    func openCurrentFileInApplication(_ application: ReaderExternalApplication?) {
        document.openInApplication(application)
    }

    func revealCurrentFileInFinder() {
        document.revealInFinder()
    }

    func presentError(_ error: Error) {
        handle(error)
    }

    func startWatchingCurrentFile() {
        guard let fileURL else {
            return
        }

        do {
            try file.watcher.startWatching(fileURL: fileURL) { [weak self] in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.handleObservedFileChange()
                }
            }
        } catch {
            handle(error)
        }
    }


    func handle(_ error: Error) {
        document.handle(error)
    }

    func clearLastError() {
        document.clearLastError()
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
