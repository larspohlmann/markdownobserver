import Foundation
import Combine
import OSLog

@MainActor
final class ReaderStore: ObservableObject {
    private static let draftPreviewRenderDebounceInterval: Duration = .milliseconds(5)
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ReaderStore"
    )

    @Published private(set) var fileURL: URL?
    @Published private(set) var fileDisplayName: String = ""
    @Published private(set) var sourceMarkdown: String = ""
    @Published private(set) var sourceEditorSeedMarkdown: String = ""
    @Published private(set) var renderedHTMLDocument: String = ""
    @Published private(set) var documentViewMode: ReaderDocumentViewMode = .preview
    @Published private(set) var documentLoadState: ReaderDocumentLoadState = .ready
    @Published private(set) var changedRegions: [ChangedRegion] = []
    @Published private(set) var unsavedChangedRegions: [ChangedRegion] = []
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastExternalChangeAt: Date?
    @Published private(set) var fileLastModifiedAt: Date?
    @Published private(set) var hasUnacknowledgedExternalChange = false
    @Published private(set) var openInApplications: [ReaderExternalApplication] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isCurrentFileMissing = false
    @Published private(set) var isSourceEditing = false
    @Published private(set) var hasUnsavedDraftChanges = false
    @Published private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    @Published private(set) var lastWatchedFolderEventAt: Date?
    @Published private(set) var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    @Published var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?
    @Published private(set) var needsImageDirectoryAccess = false

    var windowTitle: String {
        fileDisplayName.isEmpty ? "MarkdownObserver" : "\(fileDisplayName) - MarkdownObserver"
    }

    var decoratedWindowTitle: String {
        (hasUnacknowledgedExternalChange || hasUnsavedDraftChanges) ? "* \(windowTitle)" : windowTitle
    }

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

    private var settingsCancellable: AnyCancellable?

    // MARK: - Internal: accessible to Coordination extensions
    // Swift requires at least `internal` visibility for stored properties that are
    // read or mutated from extensions declared in separate files.  These properties
    // are implementation details of the store's coordination layer and must not be
    // accessed directly from outside the Stores/ group.
    let diffBaselineTracker: DiffBaselineTracking
    var securityScopeToken: SecurityScopedAccessToken?
    var documentDirectoryScopeToken: SecurityScopedAccessToken?
    var folderSecurityScopeToken: SecurityScopedAccessToken?
    var currentAccessibleFileURL: URL?
    var currentAccessibleFileURLSource: String?
    var currentOpenOrigin: ReaderOpenOrigin = .manual
    var savedMarkdown: String = ""
    var draftMarkdown: String?
    var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)?
    var onFolderWatchStopped: (() -> Void)?

    private var pendingSavedDraftDiffBaselineMarkdown: String?
    private var pendingDraftPreviewRenderTask: Task<Void, Never>?
    private var folderWatchEventDispatchCoordinator = ReaderFolderWatchEventDispatchCoordinator()

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
        requestWatchedFolderReauthorization: ((URL) -> URL?)? = nil
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
        if let requestWatchedFolderReauthorization {
            self.requestWatchedFolderReauthorization = requestWatchedFolderReauthorization
        } else {
            self.requestWatchedFolderReauthorization = { folderURL in
                MarkdownOpenPanel.pickFolder(
                    directoryURL: folderURL,
                    title: "Reauthorize Watched Folder",
                    message: "MarkdownObserver needs write access to this watched folder to save auto-opened documents.",
                    prompt: "Grant Access"
                )
            }
        }

        settingsCancellable = settingsStore.settingsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                let lookbackInterval = settings.diffBaselineLookback.timeInterval
                self.diffBaselineTracker.updateMinimumAge(lookbackInterval)
                self.folderWatchAutoOpenPlanner.updateMinimumDiffBaselineAge(lookbackInterval)
                self.rerenderWithCurrentSettings()
            }
    }

    convenience init() {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let settingsStore = ReaderSettingsStore()
        self.init(
            renderer: MarkdownRenderingService(),
            differ: ChangedRegionDiffer(),
            fileWatcher: FileChangeWatcher(),
            folderWatcher: FolderChangeWatcher(),
            settingsStore: settingsStore,
            securityScope: SecurityScopedResourceAccess(),
            fileActions: ReaderFileActionService(),
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
                minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
            ),
            settler: settler
        )
        configureSettler(settler)
    }

    convenience init(settingsStore: ReaderSettingsStoring) {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        self.init(
            renderer: MarkdownRenderingService(),
            differ: ChangedRegionDiffer(),
            fileWatcher: FileChangeWatcher(),
            folderWatcher: FolderChangeWatcher(),
            settingsStore: settingsStore,
            securityScope: SecurityScopedResourceAccess(),
            fileActions: ReaderFileActionService(),
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
                minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
            ),
            settler: settler
        )
        configureSettler(settler)
    }

    func configureSettler(_ settler: ReaderAutoOpenSettler) {
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
                self?.documentLoadState = state
            }
        )
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    var hasOpenDocument: Bool {
        fileURL != nil
    }

    var isDeferredDocument: Bool {
        documentLoadState == .deferred
    }

    var canStartSourceEditing: Bool {
        hasOpenDocument && !isCurrentFileMissing && !isSourceEditing
    }

    var canSaveSourceDraft: Bool {
        isSourceEditing && hasUnsavedDraftChanges
    }

    var canDiscardSourceDraft: Bool {
        isSourceEditing
    }

    var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let lastExternalChangeAt {
            return .updated(lastExternalChangeAt)
        }

        if let fileLastModifiedAt {
            return .lastModified(fileLastModifiedAt)
        }

        if let lastRefreshAt {
            return .updated(lastRefreshAt)
        }

        return nil
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
            documentViewMode = .preview
            return
        }

        guard documentViewMode != mode else {
            return
        }

        documentViewMode = mode
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
        lastExternalChangeAt = Date()
        hasUnacknowledgedExternalChange = true
    }

    func clearExternalChangeIndicator() {
        hasUnacknowledgedExternalChange = false
    }

    func deferFile(at url: URL, origin: ReaderOpenOrigin = .folderWatchInitialBatchAutoOpen, folderWatchSession: ReaderFolderWatchSession?) {
        let normalizedURL = Self.normalizedFileURL(url)
        fileURL = normalizedURL
        fileDisplayName = normalizedURL.lastPathComponent
        documentLoadState = .deferred
        currentOpenOrigin = origin
        lastError = nil
        isCurrentFileMissing = false
        fileLastModifiedAt = (try? FileManager.default.attributesOfItem(atPath: normalizedURL.path))?[.modificationDate] as? Date
        if let folderWatchSession {
            activeFolderWatchSession = folderWatchSession
        }
    }

    func transitionToLoading() {
        guard documentLoadState == .deferred || documentLoadState == .ready else { return }
        documentLoadState = .loading
    }

    func clearLoadingState() {
        guard documentLoadState == .loading else { return }
        documentLoadState = .ready
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
        securityScopeToken?.endAccess()
        securityScopeToken = nil
        documentDirectoryScopeToken?.endAccess()
        documentDirectoryScopeToken = nil
        currentAccessibleFileURL = nil
        currentAccessibleFileURLSource = nil
        currentOpenOrigin = .manual

        fileURL = nil
        fileDisplayName = ""
        savedMarkdown = ""
        draftMarkdown = nil
        pendingSavedDraftDiffBaselineMarkdown = nil
        sourceMarkdown = ""
        sourceEditorSeedMarkdown = ""
        renderedHTMLDocument = ""
        documentViewMode = .preview
        documentLoadState = .ready
        changedRegions = []
        unsavedChangedRegions = []
        lastRefreshAt = nil
        lastExternalChangeAt = nil
        fileLastModifiedAt = nil
        hasUnacknowledgedExternalChange = false
        openInApplications = []
        lastError = nil
        isCurrentFileMissing = false
        isSourceEditing = false
        hasUnsavedDraftChanges = false
        needsImageDirectoryAccess = false

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
            savedMarkdown = draftMarkdown
            let transition = sourceEditingCoordinator.finishSession(markdown: draftMarkdown)
            applySourceEditingTransition(transition)
            changedRegions = changedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            fileLastModifiedAt = documentIO.modificationDate(for: fileURL)
            pendingSavedDraftDiffBaselineMarkdown = changedRegions.isEmpty ? nil : diffBaselineMarkdown
            hasUnacknowledgedExternalChange = false
            isCurrentFileMissing = false
            try renderCurrentMarkdownImmediately()
            lastError = nil
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
        draftMarkdown = transition.draftMarkdown
        sourceMarkdown = transition.sourceMarkdown
        sourceEditorSeedMarkdown = transition.sourceEditorSeedMarkdown
        unsavedChangedRegions = transition.unsavedChangedRegions
        isSourceEditing = transition.isSourceEditing
        hasUnsavedDraftChanges = transition.hasUnsavedDraftChanges
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


    func increaseFontSize(step: Double = 1.0) {
        let next = settingsStore.currentSettings.baseFontSize + step
        settingsStore.updateBaseFontSize(next)
    }

    func decreaseFontSize(step: Double = 1.0) {
        let next = settingsStore.currentSettings.baseFontSize - step
        settingsStore.updateBaseFontSize(next)
    }

    func resetFontSize() {
        settingsStore.updateBaseFontSize(ReaderSettings.default.baseFontSize)
    }

    func refreshOpenInApplications() {
        guard let fileURL else {
            openInApplications = []
            return
        }

        do {
            openInApplications = try fileActions.registeredApplications(for: fileURL)
        } catch {
            openInApplications = []
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
            lastError = nil
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
            lastError = nil
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

    private func rerenderWithCurrentSettings() {
        guard fileURL != nil else {
            return
        }

        do {
            try renderCurrentMarkdownImmediately()
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
                self.lastError = nil
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
        lastRefreshAt = Date()
    }

    private func renderCurrentMarkdown() throws {
        let settings = settingsStore.currentSettings
        let theme = settings.readerTheme.themeDefinition

        let docDir = fileURL?.deletingLastPathComponent()
        activateTrustedImageFolderAccessIfNeeded(for: docDir)

        let imageResult = MarkdownImageResolver.resolve(
            markdown: sourceMarkdown,
            documentDirectoryURL: docDir
        )

        needsImageDirectoryAccess = imageResult.needsDirectoryAccess

        let rendered = try renderer.render(
            markdown: imageResult.markdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            theme: theme,
            syntaxTheme: settings.syntaxTheme,
            baseFontSize: settings.baseFontSize
        )

        renderedHTMLDocument = rendered.htmlDocument
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
            hasUnacknowledgedExternalChange = false
        }
        isCurrentFileMissing = false
        lastError = nil
    }

    private func applyLoadedDocumentState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        self.fileURL = fileURL
        fileDisplayName = fileURL.lastPathComponent
        savedMarkdown = loaded.markdown
        draftMarkdown = nil
        pendingSavedDraftDiffBaselineMarkdown = nil
        sourceMarkdown = loaded.markdown
        sourceEditorSeedMarkdown = loaded.markdown
        fileLastModifiedAt = loaded.modificationDate

        if resetDocumentViewMode {
            documentViewMode = .preview
        }

        changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        unsavedChangedRegions = []
        isSourceEditing = false
        hasUnsavedDraftChanges = false
    }

    func presentMissingDocument(at fileURL: URL, error: Error) {
        self.fileURL = fileURL
        fileDisplayName = fileURL.lastPathComponent
        fileLastModifiedAt = nil
        openInApplications = []
        isCurrentFileMissing = true
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
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
        guard let diffBaselineMarkdown = pendingSavedDraftDiffBaselineMarkdown,
              let fileURL,
              !isSourceEditing else {
            return false
        }

        let accessibleURL = effectiveAccessibleFileURL(for: fileURL, reason: "read")
        guard let loaded = try? documentIO.load(at: accessibleURL) else {
            pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        guard loaded.markdown == sourceMarkdown else {
            pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        fileLastModifiedAt = loaded.modificationDate
        changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        unsavedChangedRegions = []
        pendingSavedDraftDiffBaselineMarkdown = nil
        return true
    }

    func loadMarkdownFile(at url: URL) throws -> (markdown: String, modificationDate: Date) {
        let accessibleURL = effectiveAccessibleFileURL(for: url, reason: "read")
        return try documentIO.load(at: accessibleURL)
    }

    func saveLogContext(for url: URL?) -> String {
        let filePath = redactedPathText(for: url)
        let watchedFolderPath = redactedPathText(for: activeFolderWatchSession?.folderURL)
        let fileScopeURL = redactedPathText(for: securityScopeToken?.url)
        let folderScopeURL = redactedPathText(for: folderSecurityScopeToken?.url)
        let accessibleFilePath = redactedPathText(for: currentAccessibleFileURL)
        return "file=\(filePath) origin=\(currentOpenOrigin.rawValue) editing=\(isSourceEditing) unsaved=\(hasUnsavedDraftChanges) fileScope=\(securityScopeToken != nil) fileScopeStarted=\(securityScopeToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(folderSecurityScopeToken != nil) folderScopeStarted=\(folderSecurityScopeToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
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
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func clearLastError() {
        lastError = nil
    }

    static func normalizedFileURL(_ url: URL) -> URL {
        ReaderFileRouting.normalizedFileURL(url)
    }

    static func isSupportedMarkdownFileURL(_ url: URL) -> Bool {
        ReaderFileRouting.isSupportedMarkdownFileURL(url)
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testSetFileURL(_ url: URL?) { fileURL = url }
    func testSetFileDisplayName(_ name: String) { fileDisplayName = name }
    func testSetFileLastModifiedAt(_ date: Date?) { fileLastModifiedAt = date }
    func testSetHasUnacknowledgedExternalChange(_ value: Bool) { hasUnacknowledgedExternalChange = value }
    func testSetIsCurrentFileMissing(_ value: Bool) { isCurrentFileMissing = value }
    #endif
}
