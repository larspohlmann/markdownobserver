import Foundation
import Combine
import Observation
import OSLog

@MainActor
@Observable
final class ReaderStore {
    private static let draftPreviewRenderDebounceInterval: Duration = .milliseconds(5)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderStore"
    )

    var identity = DocumentIdentity.empty
    var content = DocumentContent.empty
    var editing = DocumentEditing.empty
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    private(set) var lastWatchedFolderEventAt: Date?
    private(set) var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
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
    var tocHeadings: [TOCHeading] = []
    var isTOCVisible: Bool = false
    var tocScrollRequest: TOCScrollRequest?
    var tocScrollRequestCounter = 0

    private let renderer: MarkdownRendering
    private let differ: ChangedRegionDiffering
    let fileWatcher: FileChangeWatching
    let folderWatcher: FolderChangeWatching
    let settingsStore: ReaderSettingsStoring
    let securityScope: SecurityScopedResourceAccessing
    private let fileActions: ReaderFileActionHandling
    let systemNotifier: ReaderSystemNotifying
    let folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning
    let sourceEditingCoordinator = ReaderSourceEditingCoordinator()
    private(set) var settler: ReaderAutoOpenSettling
    private let documentIO: ReaderDocumentIO
    let requestWatchedFolderReauthorization: (URL) -> URL?

    @ObservationIgnored var onExternalChangeKindChanged: (() -> Void)?
    @ObservationIgnored private var settingsCancellable: AnyCancellable?
    @ObservationIgnored private var appearanceOverride: LockedAppearance?
    private(set) var needsAppearanceRender = false

    // MARK: - Internal: accessible to Coordination extensions
    // These properties exist for coordination extensions in Stores/Coordination/.
    // They must be at least `internal` because Swift extensions in separate files
    // cannot see `private` members.  Do not access them from views or other stores.
    //
    // - diffBaselineTracker: read-only (`let`) — used by ExternalChangeFlow
    // - scopeContext: read/write — used by SecurityScopeFlow, FolderWatchLifecycleFlow
    // - onFolderWatchStarted/Stopped: read-only from extensions (called, never reassigned);
    //   set exclusively through setFolderWatchStateCallbacks(_:onStopped:)
    let diffBaselineTracker: DiffBaselineTracking
    var scopeContext = SecurityScopeContext()
    private(set) var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)?
    private(set) var onFolderWatchStopped: (() -> Void)?

    @ObservationIgnored private var pendingDraftPreviewRenderTask: Task<Void, Never>?
    @ObservationIgnored private var folderWatchEventDispatchCoordinator = ReaderFolderWatchEventDispatchCoordinator()

    init(
        renderer: MarkdownRendering,
        differ: ChangedRegionDiffering,
        fileWatcher: FileChangeWatching,
        folderWatcher: FolderChangeWatching,
        settingsStore: ReaderSettingsStoring,
        securityScope: SecurityScopedResourceAccessing,
        fileActions: ReaderFileActionHandling,
        systemNotifier: ReaderSystemNotifying,
        folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning,
        settler: ReaderAutoOpenSettling,
        documentIO: ReaderDocumentIO = ReaderDocumentIOService(),
        diffBaselineTracker: DiffBaselineTracking? = nil,
        requestWatchedFolderReauthorization: @escaping (URL) -> URL?
    ) {
        self.renderer = renderer
        self.differ = differ
        self.fileWatcher = fileWatcher
        self.folderWatcher = folderWatcher
        self.settingsStore = settingsStore
        self.securityScope = securityScope
        self.fileActions = fileActions
        self.systemNotifier = systemNotifier
        self.folderWatchAutoOpenPlanner = folderWatchAutoOpenPlanner
        self.settler = settler
        self.documentIO = documentIO
        self.diffBaselineTracker = diffBaselineTracker ?? DiffBaselineTracker(
            minimumAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
        )
        self.requestWatchedFolderReauthorization = requestWatchedFolderReauthorization

        settingsCancellable = settingsStore.settingsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let lookbackInterval = settings.diffBaselineLookback.timeInterval
                if lookbackInterval != self.diffBaselineTracker.currentMinimumAge {
                    self.diffBaselineTracker.updateMinimumAge(lookbackInterval)
                    self.folderWatchAutoOpenPlanner.updateMinimumDiffBaselineAge(lookbackInterval)
                }
            }

        settler.configure(
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
        let modificationDate = documentIO.modificationDate(for: normalizedURL)
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
        fileWatcher.stopWatching()
        scopeContext.endFileAndDirectoryAccess()

        identity = .empty
        content = .empty
        editing = .empty

        settler.clearSettling()
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchAutoOpenWarning = nil
    }

    func persistSourceDraft(
        _ draftMarkdown: String,
        to fileURL: URL,
        diffBaselineMarkdown: String,
        recoveryAttempted: Bool
    ) throws {
        do {
            let accessibleURL = effectiveAccessibleFileURL(for: fileURL, reason: "write")
            try documentIO.write(draftMarkdown, to: accessibleURL)
            content.savedMarkdown = draftMarkdown
            let transition = sourceEditingCoordinator.finishSession(markdown: draftMarkdown)
            applySourceEditingTransition(transition)
            content.changedRegions = changedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            content.fileLastModifiedAt = documentIO.modificationDate(for: fileURL)
            editing.pendingSavedDraftDiffBaselineMarkdown = content.changedRegions.isEmpty ? nil : diffBaselineMarkdown
            content.hasUnacknowledgedExternalChange = false
            content.unacknowledgedExternalChangeKind = .modified
            identity.isCurrentFileMissing = false
            try renderCurrentMarkdownImmediately()
            identity.lastError = nil
            let modifiedAtDescription = fileLastModifiedAt?.description ?? "nil"
            logSaveInfo(
                "save succeeded: \(saveLogContext(for: fileURL)) modifiedAt=\(modifiedAtDescription) recoveryAttempted=\(recoveryAttempted)"
            )
        } catch {
            logSaveError(
                "save failed: \(saveLogContext(for: fileURL)) error=\(error.localizedDescription) recoveryAttempted=\(recoveryAttempted)"
            )

            guard !recoveryAttempted,
                  tryReauthorizeWatchedFolderIfNeeded(after: error, for: fileURL) else {
                throw error
            }

            logSaveInfo(
                "save retrying after watched-folder reauthorization: \(saveLogContext(for: fileURL))"
            )
            try persistSourceDraft(
                draftMarkdown,
                to: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                recoveryAttempted: true
            )
        }
    }

    func applySourceEditingTransition(_ transition: ReaderSourceEditingTransition) {
        editing.draftMarkdown = transition.draftMarkdown
        content.sourceMarkdown = transition.sourceMarkdown
        editing.sourceEditorSeedMarkdown = transition.sourceEditorSeedMarkdown
        editing.unsavedChangedRegions = transition.unsavedChangedRegions
        editing.isSourceEditing = transition.isSourceEditing
        editing.hasUnsavedDraftChanges = transition.hasUnsavedDraftChanges
    }

    func handleObservedWatchedFolderChanges(_ markdownFileEvents: [ReaderFolderWatchChangeEvent]) {
        guard let session = activeFolderWatchSession else {
            return
        }

        lastWatchedFolderEventAt = .now
        let livePlan = liveFolderWatchAutoOpenPlan(for: markdownFileEvents, session: session)
        updateFolderWatchAutoOpenWarning(livePlan.warning)
        dispatchLiveFolderWatchAutoOpenEvents(
            livePlan.autoOpenEvents,
            session: session,
            origin: .folderWatchAutoOpen
        )
    }

    private func liveFolderWatchAutoOpenPlan(
        for markdownFileEvents: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession
    ) -> ReaderFolderWatchAutoOpenPlan {
        folderWatchAutoOpenPlanner.livePlan(
            for: markdownFileEvents,
            activeSession: session,
            currentDocumentFileURL: fileURLForCurrentDocument
        )
    }

    private func updateFolderWatchAutoOpenWarning(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        if let warning {
            folderWatchAutoOpenWarning = warning
        }
    }

    private func dispatchLiveFolderWatchAutoOpenEvents(
        _ plannedEvents: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        folderWatchEventDispatchCoordinator.dispatchLiveEvents(
            plannedEvents,
            session: session,
            origin: origin
        ) { [self] event, eventSession, eventOrigin in
            openPrimaryFolderWatchAutoOpenEvent(
                event,
                session: eventSession,
                origin: eventOrigin
            )
        }
    }

    private func openPrimaryFolderWatchAutoOpenEvent(
        _ event: ReaderFolderWatchChangeEvent,
        session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        openFile(
            at: event.fileURL,
            origin: origin,
            folderWatchSession: session,
            initialDiffBaselineMarkdown: event.kind == .modified ? event.previousMarkdown : nil
        )
    }

    func openInitialMarkdownFilesFromWatchedFolder(
        _ markdownFileEvents: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession
    ) {
        folderWatchEventDispatchCoordinator.dispatchInitialEvents(
            markdownFileEvents,
            session: session
        ) { [self] event, eventSession, eventOrigin in
            openPrimaryFolderWatchAutoOpenEvent(
                event,
                session: eventSession,
                origin: eventOrigin
            )
        }
    }

    func refreshOpenInApplications() {
        guard let fileURL else {
            identity.openInApplications = []
            return
        }

        do {
            identity.openInApplications = try fileActions.registeredApplications(for: fileURL)
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
            try fileActions.open(fileURL: fileURL, in: application)
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
            try fileActions.revealInFinder(fileURL: fileURL)
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
            try fileWatcher.startWatching(fileURL: fileURL) { [weak self] in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.handleObservedFileChange()
                }
            }
        } catch {
            handle(error)
        }
    }

    func scheduleDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: Self.draftPreviewRenderDebounceInterval)

            guard !Task.isCancelled else {
                return
            }

            self.pendingDraftPreviewRenderTask = nil

            do {
                try self.renderCurrentMarkdownImmediately()
                self.identity.lastError = nil
            } catch {
                self.handle(error)
            }
        }
    }

    func cancelPendingDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = nil
    }

    func renderCurrentMarkdownImmediately() throws {
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        content.lastRefreshAt = Date()
    }

    func renderWithAppearance(_ appearance: LockedAppearance) throws {
        appearanceOverride = appearance
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        needsAppearanceRender = false
        content.lastRefreshAt = Date()
    }

    func setAppearanceOverride(_ appearance: LockedAppearance) {
        appearanceOverride = appearance
        needsAppearanceRender = true
    }

    func clearAppearanceOverride() {
        appearanceOverride = nil
        needsAppearanceRender = false
    }

    private func renderCurrentMarkdown() throws {
        let settings = settingsStore.currentSettings
        let effectiveThemeKind = appearanceOverride?.readerTheme ?? settings.readerTheme
        let effectiveFontSize = appearanceOverride?.baseFontSize ?? settings.baseFontSize
        let effectiveSyntaxTheme = appearanceOverride?.syntaxTheme ?? settings.syntaxTheme
        let theme = effectiveThemeKind.themeDefinition

        let docDir = fileURL?.deletingLastPathComponent()
        activateTrustedImageFolderAccessIfNeeded(for: docDir)

        let imageResult = MarkdownImageResolver.resolve(
            markdown: sourceMarkdown,
            documentDirectoryURL: docDir
        )

        identity.needsImageDirectoryAccess = imageResult.needsDirectoryAccess

        let rendered = try renderer.render(
            markdown: imageResult.markdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            theme: theme,
            syntaxTheme: effectiveSyntaxTheme,
            baseFontSize: effectiveFontSize
        )

        content.renderedHTMLDocument = rendered.htmlDocument
        needsAppearanceRender = false
    }

    func presentLoadedDocument(
        _ loaded: (markdown: String, modificationDate: Date),
        at fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws {
        cancelPendingDraftPreviewRender()
        applyLoadedDocumentState(
            loaded,
            presentedAs: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode
        )
        try renderCurrentMarkdownImmediately()
        if acknowledgeExternalChange {
            content.hasUnacknowledgedExternalChange = false
            content.unacknowledgedExternalChangeKind = .modified
        }
        identity.isCurrentFileMissing = false
        identity.lastError = nil
    }

    private func applyLoadedDocumentState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        identity.fileURL = fileURL
        identity.fileDisplayName = fileURL.lastPathComponent
        content.savedMarkdown = loaded.markdown
        editing.draftMarkdown = nil
        editing.pendingSavedDraftDiffBaselineMarkdown = nil
        content.sourceMarkdown = loaded.markdown
        editing.sourceEditorSeedMarkdown = loaded.markdown
        content.fileLastModifiedAt = loaded.modificationDate

        if resetDocumentViewMode {
            editing.documentViewMode = .preview
        }

        content.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        editing.unsavedChangedRegions = []
        editing.isSourceEditing = false
        editing.hasUnsavedDraftChanges = false
        tocHeadings = []
        isTOCVisible = false
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        identity.fileURL = fileURL
        identity.fileDisplayName = fileURL.lastPathComponent
        content.fileLastModifiedAt = nil
        identity.openInApplications = []
        identity.isCurrentFileMissing = true
        identity.lastError = ReaderPresentableError(from: error)
        settler.clearSettling()
    }

    func changedRegions(
        diffBaselineMarkdown: String?,
        newMarkdown: String
    ) -> [ChangedRegion] {
        guard let diffBaselineMarkdown else {
            return []
        }

        return differ.computeChangedRegions(
            oldMarkdown: diffBaselineMarkdown,
            newMarkdown: newMarkdown
        )
    }

    func handlePendingSavedDraftChangeIfNeeded() -> Bool {
        guard let diffBaselineMarkdown = editing.pendingSavedDraftDiffBaselineMarkdown,
              let fileURL,
              !isSourceEditing else {
            return false
        }

        let accessibleURL = effectiveAccessibleFileURL(for: fileURL, reason: "read")
        let loaded: (markdown: String, modificationDate: Date)
        do {
            loaded = try documentIO.load(at: accessibleURL)
        } catch {
            let nsError = error as NSError
            Self.logger.error(
                "draft baseline load failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .private)"
            )
            editing.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        guard loaded.markdown == sourceMarkdown else {
            editing.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        content.fileLastModifiedAt = loaded.modificationDate
        content.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        editing.unsavedChangedRegions = []
        editing.pendingSavedDraftDiffBaselineMarkdown = nil
        return true
    }

    func loadMarkdownFile(at url: URL) throws -> (markdown: String, modificationDate: Date) {
        let accessibleURL = effectiveAccessibleFileURL(for: url, reason: "read")
        return try documentIO.load(at: accessibleURL)
    }

    func saveLogContext(for url: URL?) -> String {
        let filePath = redactedPathText(for: url)
        let watchedFolderPath = redactedPathText(for: activeFolderWatchSession?.folderURL)
        let fileScopeURL = redactedPathText(for: scopeContext.fileToken?.url)
        let folderScopeURL = redactedPathText(for: scopeContext.folderToken?.url)
        let accessibleFilePath = redactedPathText(for: scopeContext.accessibleFileURL)
        return "file=\(filePath) origin=\(identity.currentOpenOrigin.rawValue) editing=\(isSourceEditing) unsaved=\(hasUnsavedDraftChanges) fileScope=\(scopeContext.fileToken != nil) fileScopeStarted=\(scopeContext.fileToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(scopeContext.folderToken != nil) folderScopeStarted=\(scopeContext.folderToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
    }

    func redactedPathText(for url: URL?) -> String {
        guard let url else {
            return "none"
        }

        let normalizedURL = Self.normalizedFileURL(url)
        let name = normalizedURL.lastPathComponent.isEmpty ? "root" : normalizedURL.lastPathComponent
        let pathHash = String(normalizedURL.path.hashValue.magnitude, radix: 16)
        return "\(name)#\(pathHash)"
    }

    func logSaveInfo(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
    }

    func logSaveError(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
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
