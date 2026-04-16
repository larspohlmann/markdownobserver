import Foundation
import Combine
import Observation
import OSLog

@MainActor
@Observable
final class ReaderStore {
    static let draftPreviewRenderDebounceInterval: Duration = .milliseconds(5)
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderStore"
    )

    var identity = DocumentIdentity.empty
    var content = DocumentContent.empty
    var editing = DocumentEditing.empty
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    var lastWatchedFolderEventAt: Date?
    var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?

    // MARK: - Identity forwarding

    var fileURL: URL? { identity.fileURL }
    var fileDisplayName: String { identity.fileDisplayName }
    var documentLoadState: ReaderDocumentLoadState { identity.documentLoadState }
    var isCurrentFileMissing: Bool { identity.isCurrentFileMissing }
    var lastError: ReaderPresentableError? { identity.lastError }
    var openInApplications: [ReaderExternalApplication] { identity.openInApplications }
    var needsImageDirectoryAccess: Bool { identity.needsImageDirectoryAccess }
    var hasOpenDocument: Bool { identity.hasOpenDocument }
    var isDeferredDocument: Bool { identity.isDeferredDocument }
    var windowTitle: String { identity.windowTitle }

    // MARK: - Content forwarding

    var sourceMarkdown: String { content.sourceMarkdown }
    var renderedHTMLDocument: String { content.renderedHTMLDocument }
    var changedRegions: [ChangedRegion] { content.changedRegions }
    var lastRefreshAt: Date? { content.lastRefreshAt }
    var lastExternalChangeAt: Date? { content.lastExternalChangeAt }
    var fileLastModifiedAt: Date? { content.fileLastModifiedAt }
    var hasUnacknowledgedExternalChange: Bool { content.hasUnacknowledgedExternalChange }

    // MARK: - Editing forwarding

    var documentViewMode: ReaderDocumentViewMode { editing.documentViewMode }
    var sourceEditorSeedMarkdown: String { editing.sourceEditorSeedMarkdown }
    var unsavedChangedRegions: [ChangedRegion] { editing.unsavedChangedRegions }
    var isSourceEditing: Bool { editing.isSourceEditing }
    var hasUnsavedDraftChanges: Bool { editing.hasUnsavedDraftChanges }
    var canSaveSourceDraft: Bool { editing.canSaveSourceDraft }
    var canDiscardSourceDraft: Bool { editing.canDiscardSourceDraft }

    // MARK: - Cross-group computed properties

    var canStartSourceEditing: Bool {
        identity.hasOpenDocument && !identity.isCurrentFileMissing && !editing.isSourceEditing
    }

    var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let date = content.lastExternalChangeAt { return .updated(date) }
        if let date = content.fileLastModifiedAt { return .lastModified(date) }
        if let date = content.lastRefreshAt { return .updated(date) }
        return nil
    }

    var decoratedWindowTitle: String {
        (content.hasUnacknowledgedExternalChange || editing.hasUnsavedDraftChanges)
            ? "* \(identity.windowTitle)" : identity.windowTitle
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

    let rendering: ReaderRenderingDependencies
    let file: ReaderFileDependencies
    let folderWatch: ReaderFolderWatchDependencies
    let settingsStore: ReaderSettingsStoring
    let securityScopeResolver: SecurityScopeResolver
    let sourceEditingCoordinator = ReaderSourceEditingCoordinator()

    @ObservationIgnored var onExternalChangeKindChanged: (() -> Void)?
    @ObservationIgnored private var settingsCancellable: AnyCancellable?
    var needsAppearanceRender = false

    // MARK: - Internal: accessible to Coordination extensions
    // These properties exist for coordination extensions in Stores/Coordination/.
    // They must be at least `internal` because Swift extensions in separate files
    // cannot see `private` members.  Do not access them from views or other stores.
    //
    // - diffBaselineTracker: read-only (`let`) — used by ExternalChangeFlow
    // - onFolderWatchStarted/Stopped: read-only from extensions (called, never reassigned);
    //   set exclusively through setFolderWatchStateCallbacks(_:onStopped:)
    let diffBaselineTracker: DiffBaselineTracking
    private(set) var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)?
    private(set) var onFolderWatchStopped: (() -> Void)?

    @ObservationIgnored private var hasActivatedDeferredSetup = false
    @ObservationIgnored var pendingDraftPreviewRenderTask: Task<Void, Never>?
    @ObservationIgnored var appearanceOverride: LockedAppearance?
    @ObservationIgnored var folderWatchEventDispatchCoordinator = ReaderFolderWatchEventDispatchCoordinator()

    init(
        rendering: ReaderRenderingDependencies,
        file: ReaderFileDependencies,
        folderWatch: ReaderFolderWatchDependencies,
        settingsStore: ReaderSettingsStoring,
        securityScopeResolver: SecurityScopeResolver,
        diffBaselineTracker: DiffBaselineTracking? = nil
    ) {
        self.rendering = rendering
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
                self?.identity.documentLoadState = state
            }
        )
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    var currentSettings: ReaderSettings {
        settingsStore.currentSettings
    }

    func setOpenAdditionalDocumentForFolderWatchEventHandler(
        _ handler: @escaping (ReaderFolderWatchChangeEvent, ReaderFolderWatchSession?, ReaderOpenOrigin) -> Void
    ) {
        folderWatchEventDispatchCoordinator.setAdditionalOpenHandler(handler)
    }

    func setDocumentViewMode(_ mode: ReaderDocumentViewMode) {
        guard hasOpenDocument else {
            editing.documentViewMode = .preview
            return
        }

        guard documentViewMode != mode else {
            return
        }

        editing.documentViewMode = mode
    }

    func toggleDocumentViewMode() {
        setDocumentViewMode(documentViewMode.next)
    }

    func setFolderWatchStateCallbacks(
        onStarted: ((ReaderFolderWatchSession) -> Void)?,
        onStopped: (() -> Void)?
    ) {
        onFolderWatchStarted = onStarted
        onFolderWatchStopped = onStopped
    }

    func setActiveFolderWatchSession(_ session: ReaderFolderWatchSession?) {
        activeFolderWatchSession = session
    }

    func setLastWatchedFolderEventAt(_ date: Date?) {
        lastWatchedFolderEventAt = date
    }

    func setFolderWatchAutoOpenWarning(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchAutoOpenWarning = warning
    }

    func noteObservedExternalChange(kind: ReaderExternalChangeKind = .modified) {
        let previousKind = content.unacknowledgedExternalChangeKind
        let wasAcknowledged = !content.hasUnacknowledgedExternalChange
        content.lastExternalChangeAt = Date()
        content.hasUnacknowledgedExternalChange = true
        content.unacknowledgedExternalChangeKind = kind
        if !wasAcknowledged && previousKind != kind {
            onExternalChangeKindChanged?()
        }
    }

    func clearExternalChangeIndicator() {
        content.hasUnacknowledgedExternalChange = false
        content.unacknowledgedExternalChangeKind = .modified
    }

    func deferFile(at url: URL, origin: ReaderOpenOrigin = .folderWatchInitialBatchAutoOpen, folderWatchSession: ReaderFolderWatchSession?) {
        let normalizedURL = Self.normalizedFileURL(url)
        identity.fileURL = normalizedURL
        identity.fileDisplayName = normalizedURL.lastPathComponent
        identity.documentLoadState = .deferred
        identity.currentOpenOrigin = origin
        identity.lastError = nil
        identity.isCurrentFileMissing = false
        let modificationDate = file.io.modificationDate(for: normalizedURL)
        content.fileLastModifiedAt = modificationDate == .distantPast ? nil : modificationDate
        if let folderWatchSession {
            activeFolderWatchSession = folderWatchSession
        }
    }

    func transitionToLoading() {
        guard documentLoadState == .deferred || documentLoadState == .ready else { return }
        identity.documentLoadState = .loading
    }

    func clearLoadingState() {
        guard documentLoadState == .loading else { return }
        identity.documentLoadState = .ready
    }

    @ObservationIgnored private var loadingOverlayHoldGeneration: UInt = 0

    func holdLoadingOverlayBriefly() {
        // After file I/O completes the settler sets .ready immediately,
        // but the WKWebView still needs time to render.  Re-enter .loading
        // briefly so the overlay stays visible while the web view catches up.
        guard documentLoadState == .ready else { return }
        transitionToLoading()

        // Generation counter: rapid successive calls retire earlier timers
        // so only the most recent hold restores the state.
        loadingOverlayHoldGeneration &+= 1
        let generation = loadingOverlayHoldGeneration

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.loadingOverlayHoldGeneration == generation else { return }
            self.clearLoadingState()
        }
    }

    func clearOpenDocument() {
        cancelPendingDraftPreviewRender()
        // Note: diffBaselineTracker is intentionally NOT reset here.
        // Per-file-URL history is preserved across open/close cycles
        // so the lookback window remains time-based, not session-based.
        file.watcher.stopWatching()
        securityScopeResolver.endFileAndDirectoryAccess()

        identity = .empty
        content = .empty
        editing = .empty

        folderWatch.settler.clearSettling()
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchAutoOpenWarning = nil
    }

    func applySourceEditingTransition(_ transition: ReaderSourceEditingTransition) {
        editing.draftMarkdown = transition.draftMarkdown
        content.sourceMarkdown = transition.sourceMarkdown
        editing.sourceEditorSeedMarkdown = transition.sourceEditorSeedMarkdown
        editing.unsavedChangedRegions = transition.unsavedChangedRegions
        editing.isSourceEditing = transition.isSourceEditing
        editing.hasUnsavedDraftChanges = transition.hasUnsavedDraftChanges
    }

    func refreshOpenInApplications() {
        guard let fileURL else {
            identity.openInApplications = []
            return
        }

        do {
            identity.openInApplications = try file.actions.registeredApplications(for: fileURL)
        } catch {
            identity.openInApplications = []
            handle(error)
        }
    }

    func openCurrentFileInApplication(_ application: ReaderExternalApplication?) {
        guard let fileURL else {
            handle(ReaderError.noOpenFileInReader)
            return
        }

        do {
            try file.actions.open(fileURL: fileURL, in: application)
            identity.lastError = nil
        } catch {
            handle(error)
        }
    }

    func revealCurrentFileInFinder() {
        guard let fileURL else {
            handle(ReaderError.noOpenFileInReader)
            return
        }

        do {
            try file.actions.revealInFinder(fileURL: fileURL)
            identity.lastError = nil
        } catch {
            handle(error)
        }
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
        identity.lastError = ReaderPresentableError(from: error)
    }

    func clearLastError() {
        identity.lastError = nil
    }

    static func normalizedFileURL(_ url: URL) -> URL {
        ReaderFileRouting.normalizedFileURL(url)
    }

    static func isSupportedMarkdownFileURL(_ url: URL) -> Bool {
        ReaderFileRouting.isSupportedMarkdownFileURL(url)
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testSetFileURL(_ url: URL?) { identity.fileURL = url }
    func testSetFileDisplayName(_ name: String) { identity.fileDisplayName = name }
    func testSetFileLastModifiedAt(_ date: Date?) { content.fileLastModifiedAt = date }
    func testSetHasUnacknowledgedExternalChange(_ value: Bool) { content.hasUnacknowledgedExternalChange = value }
    func testSetIsCurrentFileMissing(_ value: Bool) { identity.isCurrentFileMissing = value }
    #endif
}
