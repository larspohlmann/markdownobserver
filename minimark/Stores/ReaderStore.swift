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

    var document = ReaderDocumentState.empty
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    private(set) var lastWatchedFolderEventAt: Date?
    private(set) var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?

    // MARK: - Forwarding computed properties (backward compat for views)

    var fileURL: URL? { document.fileURL }
    var fileDisplayName: String { document.fileDisplayName }
    var sourceMarkdown: String { document.sourceMarkdown }
    var sourceEditorSeedMarkdown: String { document.sourceEditorSeedMarkdown }
    var renderedHTMLDocument: String { document.renderedHTMLDocument }
    var documentViewMode: ReaderDocumentViewMode { document.documentViewMode }
    var documentLoadState: ReaderDocumentLoadState { document.documentLoadState }
    var changedRegions: [ChangedRegion] { document.changedRegions }
    var unsavedChangedRegions: [ChangedRegion] { document.unsavedChangedRegions }
    var lastRefreshAt: Date? { document.lastRefreshAt }
    var lastExternalChangeAt: Date? { document.lastExternalChangeAt }
    var fileLastModifiedAt: Date? { document.fileLastModifiedAt }
    var hasUnacknowledgedExternalChange: Bool { document.hasUnacknowledgedExternalChange }
    var openInApplications: [ReaderExternalApplication] { document.openInApplications }
    var lastError: ReaderPresentableError? { document.lastError }
    var isCurrentFileMissing: Bool { document.isCurrentFileMissing }
    var isSourceEditing: Bool { document.isSourceEditing }
    var hasUnsavedDraftChanges: Bool { document.hasUnsavedDraftChanges }
    var needsImageDirectoryAccess: Bool { document.needsImageDirectoryAccess }
    var windowTitle: String { document.windowTitle }
    var decoratedWindowTitle: String { document.decoratedWindowTitle }

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
                self?.document.documentLoadState = state
            }
        )
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    var hasOpenDocument: Bool { document.hasOpenDocument }
    var isDeferredDocument: Bool { document.isDeferredDocument }
    var canStartSourceEditing: Bool { document.canStartSourceEditing }
    var canSaveSourceDraft: Bool { document.canSaveSourceDraft }
    var canDiscardSourceDraft: Bool { document.canDiscardSourceDraft }
    var statusBarTimestamp: ReaderStatusBarTimestamp? { document.statusBarTimestamp }

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
            document.documentViewMode = .preview
            return
        }

        guard documentViewMode != mode else {
            return
        }

        document.documentViewMode = mode
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

    func noteObservedExternalChange() {
        document.lastExternalChangeAt = Date()
        document.hasUnacknowledgedExternalChange = true
    }

    func clearExternalChangeIndicator() {
        document.hasUnacknowledgedExternalChange = false
    }

    func deferFile(at url: URL, origin: ReaderOpenOrigin = .folderWatchInitialBatchAutoOpen, folderWatchSession: ReaderFolderWatchSession?) {
        let normalizedURL = Self.normalizedFileURL(url)
        document.fileURL = normalizedURL
        document.fileDisplayName = normalizedURL.lastPathComponent
        document.documentLoadState = .deferred
        document.currentOpenOrigin = origin
        document.lastError = nil
        document.isCurrentFileMissing = false
        let modificationDate = documentIO.modificationDate(for: normalizedURL)
        document.fileLastModifiedAt = modificationDate == .distantPast ? nil : modificationDate
        if let folderWatchSession {
            activeFolderWatchSession = folderWatchSession
        }
    }

    func transitionToLoading() {
        guard documentLoadState == .deferred || documentLoadState == .ready else { return }
        document.documentLoadState = .loading
    }

    func clearLoadingState() {
        guard documentLoadState == .loading else { return }
        document.documentLoadState = .ready
    }

    private var loadingOverlayHoldGeneration: UInt = 0

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

        document = .empty

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
            document.savedMarkdown = draftMarkdown
            let transition = sourceEditingCoordinator.finishSession(markdown: draftMarkdown)
            applySourceEditingTransition(transition)
            document.changedRegions = changedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            document.fileLastModifiedAt = documentIO.modificationDate(for: fileURL)
            document.pendingSavedDraftDiffBaselineMarkdown = document.changedRegions.isEmpty ? nil : diffBaselineMarkdown
            document.hasUnacknowledgedExternalChange = false
            document.isCurrentFileMissing = false
            try renderCurrentMarkdownImmediately()
            document.lastError = nil
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
        document.draftMarkdown = transition.draftMarkdown
        document.sourceMarkdown = transition.sourceMarkdown
        document.sourceEditorSeedMarkdown = transition.sourceEditorSeedMarkdown
        document.unsavedChangedRegions = transition.unsavedChangedRegions
        document.isSourceEditing = transition.isSourceEditing
        document.hasUnsavedDraftChanges = transition.hasUnsavedDraftChanges
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
            document.openInApplications = []
            return
        }

        do {
            document.openInApplications = try fileActions.registeredApplications(for: fileURL)
        } catch {
            document.openInApplications = []
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
            document.lastError = nil
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
            document.lastError = nil
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
                self.document.lastError = nil
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
        document.lastRefreshAt = Date()
    }

    func renderWithAppearance(_ appearance: LockedAppearance) throws {
        appearanceOverride = appearance
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        needsAppearanceRender = false
        document.lastRefreshAt = Date()
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

        document.needsImageDirectoryAccess = imageResult.needsDirectoryAccess

        let rendered = try renderer.render(
            markdown: imageResult.markdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            theme: theme,
            syntaxTheme: effectiveSyntaxTheme,
            baseFontSize: effectiveFontSize
        )

        document.renderedHTMLDocument = rendered.htmlDocument
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
            document.hasUnacknowledgedExternalChange = false
        }
        document.isCurrentFileMissing = false
        document.lastError = nil
    }

    private func applyLoadedDocumentState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        document.fileURL = fileURL
        document.fileDisplayName = fileURL.lastPathComponent
        document.savedMarkdown = loaded.markdown
        document.draftMarkdown = nil
        document.pendingSavedDraftDiffBaselineMarkdown = nil
        document.sourceMarkdown = loaded.markdown
        document.sourceEditorSeedMarkdown = loaded.markdown
        document.fileLastModifiedAt = loaded.modificationDate

        if resetDocumentViewMode {
            document.documentViewMode = .preview
        }

        document.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        document.unsavedChangedRegions = []
        document.isSourceEditing = false
        document.hasUnsavedDraftChanges = false
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        document.fileURL = fileURL
        document.fileDisplayName = fileURL.lastPathComponent
        document.fileLastModifiedAt = nil
        document.openInApplications = []
        document.isCurrentFileMissing = true
        document.lastError = ReaderPresentableError(from: error)
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
        guard let diffBaselineMarkdown = document.pendingSavedDraftDiffBaselineMarkdown,
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
            document.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        guard loaded.markdown == sourceMarkdown else {
            document.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        document.fileLastModifiedAt = loaded.modificationDate
        document.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        document.unsavedChangedRegions = []
        document.pendingSavedDraftDiffBaselineMarkdown = nil
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
        return "file=\(filePath) origin=\(document.currentOpenOrigin.rawValue) editing=\(isSourceEditing) unsaved=\(hasUnsavedDraftChanges) fileScope=\(scopeContext.fileToken != nil) fileScopeStarted=\(scopeContext.fileToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(scopeContext.folderToken != nil) folderScopeStarted=\(scopeContext.folderToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
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
        document.lastError = ReaderPresentableError(from: error)
    }

    func clearLastError() {
        document.lastError = nil
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
    func testSetHasUnacknowledgedExternalChange(_ value: Bool) { document.hasUnacknowledgedExternalChange = value }
    func testSetIsCurrentFileMissing(_ value: Bool) { document.isCurrentFileMissing = value }
    #endif
}
