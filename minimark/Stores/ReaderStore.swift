import Foundation
import Combine
import OSLog

enum ReaderDocumentViewMode: String, CaseIterable, Sendable {
    case preview
    case split
    case source

    var displayName: String {
        switch self {
        case .preview:
            return "Preview"
        case .split:
            return "Split"
        case .source:
            return "Source"
        }
    }

    var next: ReaderDocumentViewMode {
        switch self {
        case .preview:
            return .split
        case .split:
            return .source
        case .source:
            return .preview
        }
    }
}

enum ReaderDocumentLoadState: Equatable, Sendable {
    case ready
    case settlingAutoOpen
}

enum ReaderStatusBarTimestamp: Equatable, Sendable {
    case updated(Date)
    case lastModified(Date)
}

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

    var windowTitle: String {
        fileDisplayName.isEmpty ? "MarkdownObserver" : "\(fileDisplayName) - MarkdownObserver"
    }

    var decoratedWindowTitle: String {
        (hasUnacknowledgedExternalChange || hasUnsavedDraftChanges) ? "* \(windowTitle)" : windowTitle
    }

    private let renderer: MarkdownRendering
    private let differ: ChangedRegionDiffering
    private let fileWatcher: FileChangeWatching
    private let folderWatcher: FolderChangeWatching
    private let settingsStore: ReaderSettingsStoring
    private let securityScope: SecurityScopedResourceAccessing
    private let fileActions: ReaderFileActionHandling
    private let systemNotifier: ReaderSystemNotifying
    private let folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning
    private let autoOpenSettlingInterval: TimeInterval
    private let requestWatchedFolderReauthorization: (URL) -> URL?

    private var settingsCancellable: AnyCancellable?
    private var securityScopeToken: SecurityScopedAccessToken?
    private var folderSecurityScopeToken: SecurityScopedAccessToken?
    private var currentAccessibleFileURL: URL?
    private var currentAccessibleFileURLSource: String?
    private var currentOpenOrigin: ReaderOpenOrigin = .manual
    private var savedMarkdown: String = ""
    private var draftMarkdown: String?
    private var pendingSavedDraftDiffBaselineMarkdown: String?
    private var pendingAutoOpenSettlingContext: PendingAutoOpenSettlingContext?
    private var pendingAutoOpenSettlingTask: Task<Void, Never>?
    private var pendingDraftPreviewRenderTask: Task<Void, Never>?
    private var openAdditionalDocumentForFolderWatchEvent: ((ReaderFolderWatchChangeEvent, ReaderFolderWatchSession?, ReaderOpenOrigin) -> Void)?
    private var onFolderWatchStarted: ((ReaderFolderWatchSession) -> Void)?
    private var onFolderWatchStopped: (() -> Void)?

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
        autoOpenSettlingInterval: TimeInterval
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
        self.autoOpenSettlingInterval = autoOpenSettlingInterval
        self.requestWatchedFolderReauthorization = { folderURL in
            MarkdownOpenPanel.pickFolder(
                directoryURL: folderURL,
                title: "Reauthorize Watched Folder",
                message: "MarkdownObserver needs write access to this watched folder to save auto-opened documents.",
                prompt: "Grant Access"
            )
        }

        settingsCancellable = settingsStore.settingsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rerenderWithCurrentSettings()
            }
    }

    convenience init() {
        self.init(
            renderer: MarkdownRenderingService(),
            differ: ChangedRegionDiffer(),
            fileWatcher: FileChangeWatcher(),
            folderWatcher: FolderChangeWatcher(),
            settingsStore: ReaderSettingsStore(),
            securityScope: SecurityScopedResourceAccess(),
            fileActions: ReaderFileActionService(),
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
            autoOpenSettlingInterval: 1.0
        )
    }

    convenience init(settingsStore: ReaderSettingsStoring) {
        self.init(
            renderer: MarkdownRenderingService(),
            differ: ChangedRegionDiffer(),
            fileWatcher: FileChangeWatcher(),
            folderWatcher: FolderChangeWatcher(),
            settingsStore: settingsStore,
            securityScope: SecurityScopedResourceAccess(),
            fileActions: ReaderFileActionService(),
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
            autoOpenSettlingInterval: 1.0
        )
    }

    convenience init(
        renderer: MarkdownRendering,
        differ: ChangedRegionDiffering,
        fileWatcher: FileChangeWatching,
        folderWatcher: FolderChangeWatching,
        settingsStore: ReaderSettingsStoring,
        securityScope: SecurityScopedResourceAccessing,
        fileActions: ReaderFileActionHandling,
        autoOpenSettlingInterval: TimeInterval = 1.0
    ) {
        self.init(
            renderer: renderer,
            differ: differ,
            fileWatcher: fileWatcher,
            folderWatcher: folderWatcher,
            settingsStore: settingsStore,
            securityScope: securityScope,
            fileActions: fileActions,
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
            autoOpenSettlingInterval: autoOpenSettlingInterval
        )
    }

    convenience init(
        renderer: MarkdownRendering,
        differ: ChangedRegionDiffering,
        fileWatcher: FileChangeWatching,
        folderWatcher: FolderChangeWatching,
        settingsStore: ReaderSettingsStoring,
        securityScope: SecurityScopedResourceAccessing,
        fileActions: ReaderFileActionHandling,
        systemNotifier: ReaderSystemNotifying,
        autoOpenSettlingInterval: TimeInterval = 1.0
    ) {
        self.init(
            renderer: renderer,
            differ: differ,
            fileWatcher: fileWatcher,
            folderWatcher: folderWatcher,
            settingsStore: settingsStore,
            securityScope: securityScope,
            fileActions: fileActions,
            systemNotifier: systemNotifier,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
            autoOpenSettlingInterval: autoOpenSettlingInterval
        )
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    var hasOpenDocument: Bool {
        fileURL != nil
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
        openAdditionalDocumentForFolderWatchEvent = handler
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

    func startWatchingFolder(folderURL: URL, options: ReaderFolderWatchOptions) {
        do {
            prepareForFolderWatchStart()

            let accessibleFolderURL = folderURL
            let session = try activateFolderWatch(
                folderURL: accessibleFolderURL,
                options: options
            )

            finishStartingFolderWatch(session, accessibleFolderURL: accessibleFolderURL)
            try performInitialFolderWatchAutoOpenIfNeeded(
                folderURL: accessibleFolderURL,
                session: session
            )
        } catch {
            resetFolderWatchState(notifyIfNeeded: false)
            handle(error)
        }
    }

    func stopWatchingFolder() {
        let hadActiveFolderWatch = activeFolderWatchSession != nil
        resetFolderWatchState(notifyIfNeeded: hadActiveFolderWatch)

        if fileURL != nil {
            startWatchingCurrentFile()
        }
    }

    private func prepareForFolderWatchStart() {
        stopWatchingFolder()
        folderWatchAutoOpenWarning = nil
        folderWatchAutoOpenPlanner.resetTransientState()
    }

    private func activateFolderWatch(
        folderURL: URL,
        options: ReaderFolderWatchOptions
    ) throws -> ReaderFolderWatchSession {
        folderSecurityScopeToken = securityScope.beginAccess(to: folderURL)

        try folderWatcher.startWatching(
            folderURL: folderURL,
            includeSubfolders: options.scope == .includeSubfolders
        ) { [weak self] changedMarkdownEvents in
            guard let self else {
                return
            }

            Task { @MainActor [self] in
                self.handleObservedWatchedFolderChanges(changedMarkdownEvents)
            }
        }

        let session = ReaderFolderWatchSession(
            folderURL: Self.normalizedFileURL(folderURL),
            options: options,
            startedAt: .now
        )
        activeFolderWatchSession = session
        return session
    }

    private func finishStartingFolderWatch(
        _ session: ReaderFolderWatchSession,
        accessibleFolderURL: URL
    ) {
        settingsStore.addRecentWatchedFolder(accessibleFolderURL, options: session.options)
        onFolderWatchStarted?(session)
        lastWatchedFolderEventAt = nil

        if fileURL != nil {
            startWatchingCurrentFile()
        }
    }

    private func performInitialFolderWatchAutoOpenIfNeeded(
        folderURL: URL,
        session: ReaderFolderWatchSession
    ) throws {
        guard session.options.openMode == .openAllMarkdownFiles else {
            return
        }

        let initialPlan = try initialFolderWatchAutoOpenPlan(
            folderURL: folderURL,
            session: session
        )

        folderWatchAutoOpenWarning = initialPlan.warning
        openInitialMarkdownFilesFromWatchedFolder(initialPlan.autoOpenEvents, session: session)
    }

    private func initialFolderWatchAutoOpenPlan(
        folderURL: URL,
        session: ReaderFolderWatchSession
    ) throws -> ReaderFolderWatchAutoOpenPlan {
        let markdownURLs = try folderWatcher.markdownFiles(
            in: folderURL,
            includeSubfolders: session.options.scope == .includeSubfolders
        )
        let initialMarkdownEvents = markdownURLs.map {
            ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
        }

        return folderWatchAutoOpenPlanner.initialPlan(
            for: initialMarkdownEvents,
            activeSession: session,
            currentDocumentFileURL: fileURLForCurrentDocument
        )
    }

    private func resetFolderWatchState(notifyIfNeeded: Bool) {
        folderWatcher.stopWatching()
        folderWatchAutoOpenPlanner.resetTransientState()
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = nil
        activeFolderWatchSession = nil
        lastWatchedFolderEventAt = nil
        folderWatchAutoOpenWarning = nil

        if notifyIfNeeded {
            onFolderWatchStopped?()
        }
    }

    func clearOpenDocument() {
        cancelPendingDraftPreviewRender()
        fileWatcher.stopWatching()
        securityScopeToken?.endAccess()
        securityScopeToken = nil
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

        clearPendingAutoOpenSettling()
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchAutoOpenWarning = nil
    }

    func openFile(at url: URL) {
        openFile(at: url, origin: .manual)
    }

    func openFile(
        at url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        do {
            let accessibleURL = url
            let normalizedURL = Self.normalizedFileURL(accessibleURL)
            fileWatcher.stopWatching()
            activateFileSecurityScope(for: accessibleURL, reason: "open")
            bindFolderWatchSessionIfNeeded(folderWatchSession)
            let readURL = effectiveAccessibleFileURL(for: normalizedURL, reason: "open")
            currentOpenOrigin = origin
            logSaveInfo("opened document for reading: \(saveLogContext(for: normalizedURL))")

            let loaded = try loadAndPresentDocument(
                readURL: readURL,
                presentedAs: normalizedURL,
                diffBaselineMarkdown: initialDiffBaselineMarkdown,
                resetDocumentViewMode: true,
                acknowledgeExternalChange: true
            )
            applyPostOpenSideEffects(
                accessibleURL: accessibleURL,
                normalizedURL: normalizedURL,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loaded.markdown
            )
        } catch {
            handle(error)
        }
    }

    private func applyPostOpenSideEffects(
        accessibleURL: URL,
        normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String
    ) {
        setPendingAutoOpenSettlingContext(
            makePendingAutoOpenSettlingContext(
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loadedMarkdown,
                now: Date()
            )
        )
        refreshOpenInApplications()
        recordRecentManualOpenIfNeeded(accessibleURL, origin: origin)
        notifyAutoLoadedFileIfNeeded(
            normalizedURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        startWatchingCurrentFile()
    }

    private func recordRecentManualOpenIfNeeded(_ accessibleURL: URL, origin: ReaderOpenOrigin) {
        guard origin == .manual else {
            return
        }

        settingsStore.addRecentManuallyOpenedFile(accessibleURL)
    }

    private func notifyAutoLoadedFileIfNeeded(
        _ normalizedURL: URL,
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?
    ) {
        guard origin.shouldNotifyFileAutoLoaded,
              activeFolderWatchSession != nil,
              settingsStore.currentSettings.notificationsEnabled else {
            return
        }

        systemNotifier.notifyFileAutoLoaded(
            normalizedURL,
            changeKind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            watchedFolderURL: activeFolderWatchSession?.folderURL
        )
    }

    func handleIncomingOpenURL(_ url: URL) {
        handleIncomingOpenURL(url, origin: .manual)
    }

    func handleIncomingOpenURL(
        _ url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard url.isFileURL else {
            return
        }

        guard Self.isSupportedMarkdownFileURL(url) else {
            return
        }

        let normalizedIncomingURL = Self.normalizedFileURL(url)
        if let fileURL, Self.normalizedFileURL(fileURL) == normalizedIncomingURL {
            return
        }

        openFile(
            at: normalizedIncomingURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    func reloadCurrentFile(
        forceHighlight: Bool = true,
        acknowledgeExternalChange: Bool = true
    ) {
        guard let fileURL else {
            return
        }

        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: forceHighlight ? sourceMarkdown : nil,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
    }

    func refreshFromExternalChange() {
        guard settingsStore.currentSettings.autoRefreshOnExternalChange,
              !isSourceEditing else {
            return
        }
        reloadCurrentFile(
            at: fileURL,
            diffBaselineMarkdown: sourceMarkdown,
            acknowledgeExternalChange: false
        )
    }

    func handleObservedFileChange() {
        if handlePendingAutoOpenSettlingChangeIfNeeded() {
            return
        }

        if handlePendingSavedDraftChangeIfNeeded() {
            return
        }

        lastExternalChangeAt = Date()
        hasUnacknowledgedExternalChange = true
        if let fileURL,
           settingsStore.currentSettings.notificationsEnabled {
            systemNotifier.notifyExternalChange(
                for: fileURL,
                autoRefreshed: settingsStore.currentSettings.autoRefreshOnExternalChange,
                watchedFolderURL: watchedFolderURLForCurrentFile
            )
        }

        if isSourceEditing {
            return
        }

        if isCurrentFileMissing || currentDocumentHasBeenDeleted {
            reloadCurrentFile(
                at: fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: false
            )
            return
        }

        refreshFromExternalChange()
    }

    func startEditingSource() {
        guard canStartSourceEditing else {
            return
        }

        beginSourceEditingSession(with: savedMarkdown)
        isSourceEditing = true
        lastError = nil
    }

    func updateSourceDraft(_ markdown: String) {
        guard isSourceEditing else {
            return
        }

        applyDraftMarkdown(markdown, diffBaselineMarkdown: savedMarkdown)

        scheduleDraftPreviewRender()
    }

    func saveSourceDraft() {
        guard isSourceEditing,
              let draftMarkdown,
              let fileURL else {
            logSaveError("save requested without active editable document: \(saveLogContext(for: fileURL))")
            handle(ReaderError.noOpenFileInReader)
            return
        }

        do {
            logSaveInfo(
                "save requested: \(saveLogContext(for: fileURL)) draftUTF8Bytes=\(draftMarkdown.utf8.count)"
            )
            cancelPendingDraftPreviewRender()
            let diffBaselineMarkdown = savedMarkdown
            try persistSourceDraft(
                draftMarkdown,
                to: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                recoveryAttempted: false
            )
        } catch {
            handle(error)
        }
    }

    private func persistSourceDraft(
        _ draftMarkdown: String,
        to fileURL: URL,
        diffBaselineMarkdown: String,
        recoveryAttempted: Bool
    ) throws {
        do {
            try writeMarkdownFile(draftMarkdown, to: fileURL)
            savedMarkdown = draftMarkdown
            finishSourceEditingSession(with: draftMarkdown)
            changedRegions = changedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            fileLastModifiedAt = modificationDate(for: fileURL)
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

    func discardSourceDraft() {
        guard isSourceEditing else {
            return
        }

        if hasUnacknowledgedExternalChange {
            reloadCurrentFile(
                at: fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: true
            )
            return
        }

        finishSourceEditingSession(with: savedMarkdown)

        do {
            try renderCurrentMarkdownImmediately()
            lastError = nil
        } catch {
            handle(error)
        }
    }

    private func beginSourceEditingSession(with markdown: String) {
        sourceEditorSeedMarkdown = markdown
        applyDraftMarkdown(markdown, diffBaselineMarkdown: savedMarkdown)
    }

    private func applyDraftMarkdown(_ markdown: String, diffBaselineMarkdown: String) {
        draftMarkdown = markdown
        sourceMarkdown = markdown
        unsavedChangedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: markdown
        )
        hasUnsavedDraftChanges = markdown != diffBaselineMarkdown
    }

    private func finishSourceEditingSession(with markdown: String) {
        draftMarkdown = nil
        sourceMarkdown = markdown
        sourceEditorSeedMarkdown = markdown
        unsavedChangedRegions = []
        isSourceEditing = false
        hasUnsavedDraftChanges = false
    }

    private func handleObservedWatchedFolderChanges(_ markdownFileEvents: [ReaderFolderWatchChangeEvent]) {
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
        guard !plannedEvents.isEmpty else {
            return
        }

        if let openAdditionalDocumentForFolderWatchEvent {
            for event in plannedEvents {
                openAdditionalDocumentForFolderWatchEvent(event, session, origin)
            }
            return
        }

        openPrimaryFolderWatchAutoOpenEvent(plannedEvents[0], session: session, origin: origin)
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

    private func dispatchAdditionalFolderWatchAutoOpenEvents(
        _ events: ArraySlice<ReaderFolderWatchChangeEvent>,
        session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        for event in events {
            openAdditionalDocumentForFolderWatchEvent?(event, session, origin)
        }
    }

    private func openInitialMarkdownFilesFromWatchedFolder(
        _ markdownFileEvents: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession
    ) {
        guard let firstEvent = markdownFileEvents.first else {
            return
        }

        let initialOrigin: ReaderOpenOrigin = markdownFileEvents.count > 1
            ? .folderWatchInitialBatchAutoOpen
            : .folderWatchAutoOpen

        openPrimaryFolderWatchAutoOpenEvent(
            firstEvent,
            session: session,
            origin: initialOrigin
        )

        dispatchAdditionalFolderWatchAutoOpenEvents(
            markdownFileEvents.dropFirst(),
            session: session,
            origin: .folderWatchInitialBatchAutoOpen
        )
    }

    private func reloadCurrentFile(
        at fileURL: URL?,
        diffBaselineMarkdown: String?,
        acknowledgeExternalChange: Bool
    ) {
        guard let fileURL else {
            return
        }

        do {
            _ = try loadAndPresentDocument(
                readURL: fileURL,
                presentedAs: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                resetDocumentViewMode: false,
                acknowledgeExternalChange: acknowledgeExternalChange
            )
            clearPendingAutoOpenSettling()
        } catch {
            handleDocumentReloadFailure(error, for: fileURL)
        }
    }

    private var fileURLForCurrentDocument: URL? {
        guard let fileURL else {
            return nil
        }
        return Self.normalizedFileURL(fileURL)
    }

    private var watchedFolderURLForCurrentFile: URL? {
        guard let activeFolderWatchSession,
              let fileURL = fileURLForCurrentDocument else {
            return nil
        }

        let normalizedWatchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
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

    private func startWatchingCurrentFile() {
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

    private func scheduleDraftPreviewRender() {
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

    private func cancelPendingDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = nil
    }

    private func renderCurrentMarkdownImmediately() throws {
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        lastRefreshAt = Date()
    }

    private func renderCurrentMarkdown() throws {
        let settings = settingsStore.currentSettings
        let theme = ReaderTheme.theme(for: settings.readerTheme)

        let rendered = try renderer.render(
            markdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            readerTheme: theme,
            syntaxTheme: settings.syntaxTheme,
            baseFontSize: settings.baseFontSize
        )

        renderedHTMLDocument = rendered.htmlDocument
    }

    private func loadAndPresentDocument(
        readURL: URL,
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws -> (markdown: String, modificationDate: Date) {
        let loaded = try loadMarkdownFile(at: readURL)
        try presentLoadedDocument(
            loaded,
            at: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
        return loaded
    }

    private func presentLoadedDocument(
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

    private var currentDocumentHasBeenDeleted: Bool {
        guard let fileURL else {
            return false
        }

        return !FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func handleDocumentReloadFailure(_ error: Error, for fileURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            handle(error)
            return
        }

        presentMissingDocument(at: fileURL, error: error)
    }

    private func presentMissingDocument(at fileURL: URL, error: Error) {
        self.fileURL = fileURL
        fileDisplayName = fileURL.lastPathComponent
        fileLastModifiedAt = nil
        openInApplications = []
        isCurrentFileMissing = true
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        clearPendingAutoOpenSettling()
    }

    private func changedRegions(
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

    private func handlePendingSavedDraftChangeIfNeeded() -> Bool {
        guard let diffBaselineMarkdown = pendingSavedDraftDiffBaselineMarkdown,
              let fileURL,
              !isSourceEditing else {
            return false
        }

        guard let loaded = try? loadMarkdownFile(at: fileURL) else {
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

    private func handlePendingAutoOpenSettlingChangeIfNeeded() -> Bool {
        guard let fileURL else {
            return false
        }

        guard let context = pendingAutoOpenSettlingContext else {
            return false
        }

        guard let loaded = try? loadMarkdownFile(at: fileURL) else {
            return false
        }

        switch evaluatePendingAutoOpenSettling(
            context: context,
            loaded: loaded,
            presentedAs: fileURL,
            now: Date()
        ) {
        case .unhandled:
            return false
        case .handled:
            return true
        }
    }

    private func setPendingAutoOpenSettlingContext(_ context: PendingAutoOpenSettlingContext?) {
        pendingAutoOpenSettlingTask?.cancel()
        pendingAutoOpenSettlingTask = nil
        pendingAutoOpenSettlingContext = context
        documentLoadState = context?.showsLoadingOverlay == true ? .settlingAutoOpen : .ready

        guard context != nil else {
            return
        }

        schedulePendingAutoOpenSettlingCheck()
    }

    private func clearPendingAutoOpenSettling() {
        pendingAutoOpenSettlingTask?.cancel()
        pendingAutoOpenSettlingTask = nil
        pendingAutoOpenSettlingContext = nil
        documentLoadState = .ready
    }

    private func shouldSettleAutoOpenDocument(
        origin: ReaderOpenOrigin
    ) -> Bool {
        origin.isFolderWatchAutoOpen
    }

    private func shouldShowLoadingDuringAutoOpenSettling(
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String
    ) -> Bool {
        origin == .folderWatchAutoOpen &&
            initialDiffBaselineMarkdown == nil &&
            loadedMarkdown.isEmpty
    }

    private func makePendingAutoOpenSettlingContext(
        origin: ReaderOpenOrigin,
        initialDiffBaselineMarkdown: String?,
        loadedMarkdown: String,
        now: Date
    ) -> PendingAutoOpenSettlingContext? {
        guard shouldSettleAutoOpenDocument(origin: origin) else {
            return nil
        }

        let showsLoadingOverlay = shouldShowLoadingDuringAutoOpenSettling(
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
            loadedMarkdown: loadedMarkdown
        )

        return PendingAutoOpenSettlingContext(
            loadedMarkdown: loadedMarkdown,
            diffBaselineMarkdown: initialDiffBaselineMarkdown,
            expiresAt: showsLoadingOverlay ? nil : now.addingTimeInterval(autoOpenSettlingInterval),
            showsLoadingOverlay: showsLoadingOverlay
        )
    }

    private func evaluatePendingAutoOpenSettling(
        context: PendingAutoOpenSettlingContext,
        loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        now: Date
    ) -> PendingAutoOpenSettlingEvaluation {
        if let expiresAt = context.expiresAt,
           now > expiresAt {
            clearPendingAutoOpenSettling()
            return .unhandled
        }

        guard loaded.markdown != context.loadedMarkdown else {
            if !context.showsLoadingOverlay {
                clearPendingAutoOpenSettling()
            }
            return .handled
        }

        clearPendingAutoOpenSettling()

        do {
            try presentLoadedDocument(
                loaded,
                at: fileURL,
                diffBaselineMarkdown: context.diffBaselineMarkdown,
                resetDocumentViewMode: false,
                acknowledgeExternalChange: true
            )
        } catch {
            handle(error)
        }

        return .handled
    }

    private func schedulePendingAutoOpenSettlingCheck() {
        pendingAutoOpenSettlingTask?.cancel()
        pendingAutoOpenSettlingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard let context = self.pendingAutoOpenSettlingContext else {
                    return
                }

                let now = Date()
                if let expiresAt = context.expiresAt,
                   now >= expiresAt {
                    self.clearPendingAutoOpenSettling()
                    return
                }

                try? await Task.sleep(for: .milliseconds(100))

                guard !Task.isCancelled else {
                    return
                }

                guard let fileURL = self.fileURL else {
                    self.clearPendingAutoOpenSettling()
                    return
                }

                guard let loaded = try? self.loadMarkdownFile(at: fileURL) else {
                    continue
                }

                switch self.evaluatePendingAutoOpenSettling(
                    context: context,
                    loaded: loaded,
                    presentedAs: fileURL,
                    now: now
                ) {
                case .unhandled:
                    continue
                case .handled:
                    return
                }
            }
        }
    }

    private func loadMarkdownFile(at url: URL) throws -> (markdown: String, modificationDate: Date) {
        guard url.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        do {
            let accessibleURL = effectiveAccessibleFileURL(for: url, reason: "read")
            let markdown = try String(contentsOf: accessibleURL, encoding: .utf8)
                return (markdown: markdown, modificationDate: modificationDate(for: accessibleURL))
        } catch {
            throw ReaderError.fileReadFailed(url, underlying: error)
        }
    }

    private func writeMarkdownFile(_ markdown: String, to url: URL) throws {
        guard url.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        do {
            let accessibleURL = effectiveAccessibleFileURL(for: url, reason: "write")
            try markdown.write(to: accessibleURL, atomically: true, encoding: .utf8)
        } catch {
            throw ReaderError.fileWriteFailed(url, underlying: error)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        let normalizedURL = Self.normalizedFileURL(url)

        if let attributes = try? FileManager.default.attributesOfItem(atPath: normalizedURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            return modificationDate
        }

        if let values = try? normalizedURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate {
            return modificationDate
        }

        return .distantPast
    }

    private func activateFileSecurityScope(for url: URL, reason: String) {
        securityScopeToken?.endAccess()
        securityScopeToken = securityScope.beginAccess(to: url)
        if securityScopeToken?.didStartAccess == true {
            currentAccessibleFileURL = url
            currentAccessibleFileURLSource = "fileScope"
        }
        logSaveInfo(
            "file scope updated: reason=\(reason) url=\(url.path) started=\(securityScopeToken?.didStartAccess == true)"
        )
    }

    private func bindFolderWatchSessionIfNeeded(_ session: ReaderFolderWatchSession?) {
        guard let session else {
            return
        }

        activeFolderWatchSession = normalizedFolderWatchSession(session)
    }

    private func ensureFolderWatchAccessIfNeeded(for fileURL: URL, reason: String) {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL) else {
            return
        }

        if folderSecurityScopeToken?.didStartAccess == true {
            return
        }

        let accessURL = resolvedWatchedFolderAccessURL(for: activeFolderWatchSession)
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = securityScope.beginAccess(to: accessURL)
        logSaveInfo(
            "folder scope updated: reason=\(reason) watchedFolder=\(activeFolderWatchSession.folderURL.path) accessURL=\(accessURL.path) started=\(folderSecurityScopeToken?.didStartAccess == true) appliesToFile=\(fileURL.path)"
        )
    }

    private func effectiveAccessibleFileURL(for url: URL, reason: String) -> URL {
        let normalizedURL = Self.normalizedFileURL(url)
        ensureFolderWatchAccessIfNeeded(for: normalizedURL, reason: reason)

        if let securityScopeToken,
           securityScopeToken.didStartAccess,
           Self.normalizedFileURL(securityScopeToken.url) == normalizedURL {
            currentAccessibleFileURL = securityScopeToken.url
            currentAccessibleFileURLSource = "fileScope"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(normalizedURL.path) accessURL=\(securityScopeToken.url.path) source=fileScope"
            )
            return securityScopeToken.url
        }

        if let currentAccessibleFileURL,
           currentAccessibleFileURLSource == "fileScope",
           Self.normalizedFileURL(currentAccessibleFileURL) == normalizedURL {
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(normalizedURL.path) accessURL=\(currentAccessibleFileURL.path) source=cachedFileScope"
            )
            return currentAccessibleFileURL
        }

        if let folderScopedFileURL = folderScopedAccessibleFileURL(for: normalizedURL) {
            currentAccessibleFileURL = folderScopedFileURL
            currentAccessibleFileURLSource = "folderScopeChildURL"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(normalizedURL.path) accessURL=\(folderScopedFileURL.path) source=folderScopeChildURL"
            )
            return folderScopedFileURL
        }

        deriveFileSecurityScopeFromFolderIfNeeded(for: normalizedURL, reason: reason)

        if let securityScopeToken,
           securityScopeToken.didStartAccess,
           Self.normalizedFileURL(securityScopeToken.url) == normalizedURL {
            currentAccessibleFileURL = securityScopeToken.url
            currentAccessibleFileURLSource = "derivedFileScope"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(normalizedURL.path) accessURL=\(securityScopeToken.url.path) source=derivedFileScope"
            )
            return securityScopeToken.url
        }

        logSaveInfo(
            "effective file access: reason=\(reason) file=\(normalizedURL.path) accessURL=\(normalizedURL.path) source=plainURL"
        )
        return normalizedURL
    }

    private func folderScopedAccessibleFileURL(for fileURL: URL) -> URL? {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL),
              let folderSecurityScopeToken,
              folderSecurityScopeToken.didStartAccess else {
            return nil
        }

        let normalizedFileURL = Self.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
        let watchedFolderPath = normalizedWatchedFolderURL.path
        let filePath = normalizedFileURL.path

        guard filePath.hasPrefix(watchedFolderPath) else {
            return nil
        }

        let relativePath = filePath.dropFirst(watchedFolderPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            return folderSecurityScopeToken.url
        }

        return URL(fileURLWithPath: relativePath, relativeTo: folderSecurityScopeToken.url).standardizedFileURL
    }

    private func tryReauthorizeWatchedFolderIfNeeded(after error: Error, for fileURL: URL) -> Bool {
        guard isPermissionDeniedWriteError(error),
              let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL) else {
            return false
        }

        let watchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
        logSaveInfo(
            "watched-folder reauthorization requested: file=\(fileURL.path) watchedFolder=\(watchedFolderURL.path)"
        )

        guard let selectedFolderURL = requestWatchedFolderReauthorization(watchedFolderURL) else {
            logSaveInfo(
                "watched-folder reauthorization cancelled: file=\(fileURL.path) watchedFolder=\(watchedFolderURL.path)"
            )
            return false
        }

        let normalizedSelectedFolderURL = Self.normalizedFileURL(selectedFolderURL)
        guard normalizedSelectedFolderURL == watchedFolderURL else {
            logSaveError(
                "watched-folder reauthorization rejected different folder: file=\(fileURL.path) expected=\(watchedFolderURL.path) selected=\(normalizedSelectedFolderURL.path)"
            )
            return false
        }

        settingsStore.addRecentWatchedFolder(selectedFolderURL, options: activeFolderWatchSession.options)
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = securityScope.beginAccess(to: selectedFolderURL)
        self.activeFolderWatchSession = ReaderFolderWatchSession(
            folderURL: watchedFolderURL,
            options: activeFolderWatchSession.options,
            startedAt: activeFolderWatchSession.startedAt
        )
        securityScopeToken?.endAccess()
        securityScopeToken = nil
        currentAccessibleFileURL = nil
        currentAccessibleFileURLSource = nil

        logSaveInfo(
            "watched-folder reauthorization updated: file=\(fileURL.path) watchedFolder=\(watchedFolderURL.path) started=\(folderSecurityScopeToken?.didStartAccess == true)"
        )

        return folderSecurityScopeToken?.didStartAccess == true
    }

    private func isPermissionDeniedWriteError(_ error: Error) -> Bool {
        let resolvedError: NSError
        if case let ReaderError.fileWriteFailed(_, underlying) = error {
            resolvedError = underlying as NSError
        } else {
            resolvedError = error as NSError
        }

        if resolvedError.domain == NSCocoaErrorDomain,
           resolvedError.code == NSFileWriteNoPermissionError {
            return true
        }

        if resolvedError.domain == NSPOSIXErrorDomain,
              [Int(EACCES), Int(EPERM)].contains(resolvedError.code) {
            return true
        }

        return false
    }

    private func deriveFileSecurityScopeFromFolderIfNeeded(for fileURL: URL, reason: String) {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL),
              folderSecurityScopeToken?.didStartAccess == true,
              securityScopeToken?.didStartAccess != true else {
            return
        }

        do {
            let bookmarkData = try fileURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarkIsStale = false
            let scopedFileURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &bookmarkIsStale
            )
            logSaveInfo(
                "file scope derivation attempting: reason=\(reason) file=\(fileURL.path) watchedFolder=\(activeFolderWatchSession.folderURL.path) staleBookmark=\(bookmarkIsStale)"
            )
            activateFileSecurityScope(for: scopedFileURL, reason: "\(reason)-derivedFromFolder")
        } catch {
            logSaveError(
                "file scope derivation failed: reason=\(reason) file=\(fileURL.path) watchedFolder=\(activeFolderWatchSession.folderURL.path) error=\(error.localizedDescription)"
            )
        }
    }

    private func resolvedWatchedFolderAccessURL(for session: ReaderFolderWatchSession) -> URL {
        settingsStore.resolvedRecentWatchedFolderURL(matching: session.folderURL) ?? session.folderURL
    }

    private func watchedFolderSession(_ session: ReaderFolderWatchSession, appliesTo fileURL: URL) -> Bool {
        let normalizedFileURL = Self.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = Self.normalizedFileURL(session.folderURL)

        switch session.options.scope {
        case .selectedFolderOnly:
            return normalizedFileURL.deletingLastPathComponent().path == normalizedWatchedFolderURL.path
        case .includeSubfolders:
            let folderPath = normalizedWatchedFolderURL.path.hasSuffix("/")
                ? normalizedWatchedFolderURL.path
                : normalizedWatchedFolderURL.path + "/"
            return normalizedFileURL.path.hasPrefix(folderPath)
        }
    }

    private func normalizedFolderWatchSession(_ session: ReaderFolderWatchSession) -> ReaderFolderWatchSession {
        ReaderFolderWatchSession(
            folderURL: Self.normalizedFileURL(session.folderURL),
            options: session.options,
            startedAt: session.startedAt
        )
    }

    private func saveLogContext(for url: URL?) -> String {
        let filePath = url?.path ?? "none"
        let watchedFolderPath = activeFolderWatchSession?.folderURL.path ?? "none"
        let fileScopeURL = securityScopeToken?.url.path ?? "none"
        let folderScopeURL = folderSecurityScopeToken?.url.path ?? "none"
        let accessibleFilePath = currentAccessibleFileURL?.path ?? "none"
        return "file=\(filePath) origin=\(currentOpenOrigin.rawValue) editing=\(isSourceEditing) unsaved=\(hasUnsavedDraftChanges) fileScope=\(securityScopeToken != nil) fileScopeStarted=\(securityScopeToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(folderSecurityScopeToken != nil) folderScopeStarted=\(folderSecurityScopeToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
    }

    private func logSaveInfo(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
    }

    private func logSaveError(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
    }

    private func handle(_ error: Error) {
        lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func normalizedFileURL(_ url: URL) -> URL {
        ReaderFileRouting.normalizedFileURL(url)
    }

    private static func isSupportedMarkdownFileURL(_ url: URL) -> Bool {
        ReaderFileRouting.isSupportedMarkdownFileURL(url)
    }
}

private struct PendingAutoOpenSettlingContext {
    let loadedMarkdown: String
    let diffBaselineMarkdown: String?
    let expiresAt: Date?
    let showsLoadingOverlay: Bool
}

private enum PendingAutoOpenSettlingEvaluation {
    case unhandled
    case handled
}
