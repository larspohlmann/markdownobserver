import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ReaderWindowCoordinator {
    private let settingsStore: ReaderSettingsStore
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private var folderWatchOpenController: WindowFolderWatchOpenController!
    private var shellController: WindowShellController!
    private var documentOpenCoordinator: WindowDocumentOpenCoordinator!
    private var sidebarActionRouter: SidebarDocumentActionRouter!
    private var appearanceLockCoordinator: AppearanceLockCoordinator!
    private var contentViewActionRouter: ContentViewActionRouter!
    let openDocumentPathTracker = OpenDocumentPathTracker()

    // Window presentation state
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    var lastAppliedSidebarDelta: CGFloat = 0
    var isTitlebarEditingFavorites = false
    var isEditingSubfolders = false

    var hostWindow: NSWindow? { shellController.hostWindow }
    var effectiveWindowTitle: String { shellController.effectiveWindowTitle }
    var dockTileWindowToken: UUID { shellController.dockTileWindowToken }

    // Controller references (set via configure())
    private(set) var appearanceController: WindowAppearanceController?
    private(set) var groupStateController: SidebarGroupStateController?
    private(set) var favoriteWorkspaceController: FavoriteWorkspaceController?
    private(set) var folderWatchFlowController: FolderWatchFlowController?
    private(set) var uiTestLaunchCoordinator: UITestLaunchCoordinator?
    private(set) var recentHistoryCoordinator: RecentHistoryCoordinator?

    func configure(
        appearanceController: WindowAppearanceController,
        groupStateController: SidebarGroupStateController,
        favoriteWorkspaceController: FavoriteWorkspaceController,
        folderWatchFlowController: FolderWatchFlowController,
        uiTestLaunchCoordinator: UITestLaunchCoordinator,
        recentHistoryCoordinator: RecentHistoryCoordinator
    ) {
        self.appearanceController = appearanceController
        self.groupStateController = groupStateController
        self.favoriteWorkspaceController = favoriteWorkspaceController
        self.folderWatchFlowController = folderWatchFlowController
        self.uiTestLaunchCoordinator = uiTestLaunchCoordinator
        self.recentHistoryCoordinator = recentHistoryCoordinator
        documentOpenCoordinator.configureStoreCallbacks(
            lockedAppearanceProvider: { [weak appearanceController] in appearanceController?.lockedAppearance }
        )
    }

    init(
        settingsStore: ReaderSettingsStore,
        sidebarDocumentController: ReaderSidebarDocumentController
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
        self.shellController = WindowShellController(
            sidebarDocumentController: sidebarDocumentController,
            folderWatchSessionProvider: { [weak self] in
                self?.folderWatchFlowController?.sharedFolderWatchSession
            }
        )
        self.folderWatchOpenController = WindowFolderWatchOpenController(
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            isHostWindowAttached: { [weak self] in self?.hostWindow != nil },
            onAfterFlush: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.documentOpenCoordinator = WindowDocumentOpenCoordinator(
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            folderWatchOpenController: folderWatchOpenController,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            folderWatchSessionProvider: { [weak self] in
                self?.folderWatchFlowController?.sharedFolderWatchSession
            },
            applyTitlePresentation: { [weak self] in self?.applyWindowTitlePresentation() },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() },
            prepareRecentFolderWatch: { [weak self] folderURL, options in
                self?.folderWatchFlowController?.presentOptions(for: folderURL, options: options)
            }
        )
        self.sidebarActionRouter = SidebarDocumentActionRouter(
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            sidebarWidthProvider: { [weak self] in self?.sidebarWidth ?? ReaderSidebarWorkspaceMetrics.sidebarIdealWidth },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.appearanceLockCoordinator = AppearanceLockCoordinator(
            appearanceControllerProvider: { [weak self] in self?.appearanceController },
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController }
        )
        self.contentViewActionRouter = ContentViewActionRouter(
            documentOpenCoordinator: documentOpenCoordinator,
            appearanceLockCoordinator: appearanceLockCoordinator,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            folderWatchFlowControllerProvider: { [weak self] in self?.folderWatchFlowController },
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            recentHistoryCoordinatorProvider: { [weak self] in self?.recentHistoryCoordinator },
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            sidebarWidthProvider: { [weak self] in self?.sidebarWidth ?? ReaderSidebarWorkspaceMetrics.sidebarIdealWidth },
            applyTitlePresentation: { [weak self] in self?.applyWindowTitlePresentation() },
            confirmFolderWatch: { [weak self] options in self?.confirmFolderWatch(options) },
            stopFolderWatch: { [weak self] in self?.stopFolderWatch() },
            startFavoriteWatch: { [weak self] favorite in self?.startFavoriteWatch(favorite) },
            setEditingSubfolders: { [weak self] value in self?.isEditingSubfolders = value },
            setEditingFavorites: { [weak self] value in self?.isTitlebarEditingFavorites = value }
        )
    }

    var hasPendingFolderWatchOpenEvents: Bool {
        folderWatchOpenController.hasPendingEvents
    }

    func configureStoreCallbacks(
        lockedAppearanceProvider: @escaping @MainActor () -> LockedAppearance? = { nil }
    ) {
        documentOpenCoordinator.configureStoreCallbacks(lockedAppearanceProvider: lockedAppearanceProvider)
    }

    // MARK: - Window Shell Flow

    func applyWindowTitlePresentation() {
        shellController.applyTitlePresentation()
    }

    func enqueueFolderWatchOpen(
        _ event: FolderWatchChangeEvent,
        folderWatchSession: FolderWatchSession?,
        origin: ReaderOpenOrigin
    ) {
        folderWatchOpenController.enqueue(event, folderWatchSession: folderWatchSession, origin: origin)
    }

    func flushQueuedFolderWatchOpens() {
        folderWatchOpenController.flush()
    }

    func openFileRequest(_ request: FileOpenRequest) {
        documentOpenCoordinator.openFileRequest(request)
    }

    func refreshSharedFolderWatchState() {
        folderWatchFlowController?.refreshSharedState()
    }

    func refreshWindowPresentation() {
        refreshSharedFolderWatchState()
        shellController.applyTitlePresentation()
    }

    func refreshWindowShellRegistrationAndTitle() {
        shellController.refreshRegistrationAndTitle()
    }

    func refreshWindowShellState() {
        refreshSharedFolderWatchState()
        shellController.refreshRegistrationAndTitle()
    }

    func registerWindowIfNeeded() {
        shellController.registerIfNeeded()
    }

    func handleFolderWatchToolbarAction(_ action: FolderWatchToolbarAction) {
        contentViewActionRouter.handle(action)
    }

    func handleEditFavoritesAction(_ action: EditFavoritesAction) {
        contentViewActionRouter.handle(action)
    }

    func handleWindowAccessorUpdate(_ window: NSWindow?) {
        guard shellController.updateHostWindow(window) else { return }
        handleHostWindowChange()
    }

    func handleHostWindowChange() {
        refreshWindowShellState()
        uiTestLaunchCoordinator?.applyConfigurationIfNeeded()
        if hostWindow != nil, hasPendingFolderWatchOpenEvents {
            flushQueuedFolderWatchOpens()
        }
    }

    func handleFavoriteWorkspaceStateChange(_ newState: ReaderFavoriteWorkspaceState?) {
        guard let favoriteID = favoriteWorkspaceController?.activeFavoriteID, var state = newState else {
            return
        }
        state.lockedAppearance = appearanceController?.lockedAppearance
        settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
    }

    func handleGroupStateChange(
        oldSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot,
        newSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot
    ) {
        if let favoriteController = favoriteWorkspaceController, favoriteController.isActive {
            let needsUpdate =
                favoriteController.activeFavoriteWorkspaceState?.pinnedGroupIDs != newSnapshot.pinnedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.collapsedGroupIDs != newSnapshot.collapsedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.groupSortMode != newSnapshot.sortMode ||
                favoriteController.activeFavoriteWorkspaceState?.fileSortMode != newSnapshot.fileSortMode ||
                favoriteController.activeFavoriteWorkspaceState?.manualGroupOrder != newSnapshot.manualGroupOrder

            if needsUpdate {
                favoriteController.updateGroupState(
                    pinnedGroupIDs: newSnapshot.pinnedGroupIDs,
                    collapsedGroupIDs: newSnapshot.collapsedGroupIDs,
                    groupSortMode: newSnapshot.sortMode,
                    fileSortMode: newSnapshot.fileSortMode,
                    manualGroupOrder: newSnapshot.manualGroupOrder
                )
            }
        } else {
            if oldSnapshot.sortMode != newSnapshot.sortMode {
                settingsStore.updateSidebarGroupSortMode(newSnapshot.sortMode)
            }
            if oldSnapshot.fileSortMode != newSnapshot.fileSortMode {
                settingsStore.updateSidebarSortMode(newSnapshot.fileSortMode)
            }
        }
    }

    func handleDocumentListChange() {
        groupStateController?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
    }

    func handleWindowAppear() {
        groupStateController?.configureSortModes(
            sortMode: settingsStore.currentSettings.sidebarGroupSortMode,
            fileSortMode: settingsStore.currentSettings.sidebarSortMode
        )
        groupStateController?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        groupStateController?.observeRowStates(from: sidebarDocumentController)
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
        shellController.configureDockTile()
    }

    func handleWindowDisappear() {
        shellController.clearDockTile()
    }

    func handleSidebarWidthChange(_ newWidth: CGFloat) {
        sidebarWidth = newWidth
        if favoriteWorkspaceController?.activeFavoriteWorkspaceState != nil,
           sidebarDocumentController.documents.count > 1 {
            favoriteWorkspaceController?.updateSidebarWidth(newWidth)
        }
    }

    func handleSidebarVisibilityChange(oldCount: Int, newCount: Int) {
        let isSidebarVisible = newCount > 1
        let wasVisible = oldCount > 1

        guard isSidebarVisible != wasVisible, let window = hostWindow else {
            return
        }

        if isSidebarVisible, let favoriteWidth = favoriteWorkspaceController?.activeFavoriteWorkspaceState?.sidebarWidth {
            sidebarWidth = favoriteWidth
        }

        let delta = isSidebarVisible
            ? sidebarWidth
            : -lastAppliedSidebarDelta

        guard let screenFrame = window.screen?.visibleFrame else {
            return
        }

        let oldWidth = window.frame.width
        let newFrame = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: window.frame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: delta
        )

        window.setFrame(newFrame, display: true, animate: true)

        if isSidebarVisible {
            lastAppliedSidebarDelta = newFrame.width - oldWidth
        } else {
            lastAppliedSidebarDelta = 0
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
    }

    // MARK: - Open and Watch Flow

    func openIncomingURL(_ url: URL) {
        documentOpenCoordinator.openIncomingURL(url)
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        documentOpenCoordinator.openDocumentInCurrentWindow(fileURL)
    }

    func applyInitialSeedIfNeeded(seed: ReaderWindowSeed?) {
        documentOpenCoordinator.applyInitialSeedIfNeeded(seed: seed)
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        documentOpenCoordinator.openDocumentInSelectedSlot(
            at: fileURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: FolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        documentOpenCoordinator.openAdditionalDocument(
            fileURL,
            folderWatchSession: folderWatchSession,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    func openAdditionalDocumentInCurrentWindow(
        _ fileURL: URL,
        folderWatchSession: FolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        documentOpenCoordinator.openAdditionalDocumentInCurrentWindow(
            fileURL,
            folderWatchSession: folderWatchSession,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    var isSharedFolderWatchAFavorite: Bool {
        favoriteWorkspaceController?.isCurrentWatchAFavorite ?? false
    }

    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
        guard let favoriteWorkspaceController else { return }
        let restoredSidebarWidth = favoriteWorkspaceController.startFavoriteWatch(entry)
        sidebarWidth = restoredSidebarWidth
        refreshWindowPresentation()
    }

    func startWatchingFolder(
        folderURL: URL,
        options: FolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) {
        let deactivated = folderWatchFlowController?.startWatchingFolder(
            folderURL: folderURL,
            options: options,
            performInitialAutoOpen: performInitialAutoOpen
        ) ?? false
        if deactivated {
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
        refreshWindowPresentation()
    }

    func closeSidebarDocument(_ documentID: UUID) {
        sidebarActionRouter.closeDocument(documentID)
    }

    func openSidebarDocumentsInDefaultApp(_ documentIDs: Set<UUID>) {
        sidebarActionRouter.openDocumentsInDefaultApp(documentIDs)
    }

    func openSidebarDocumentsInApplication(_ application: ReaderExternalApplication, _ documentIDs: Set<UUID>) {
        sidebarActionRouter.openDocumentsInApplication(application, documentIDs)
    }

    func revealSidebarDocumentsInFinder(_ documentIDs: Set<UUID>) {
        sidebarActionRouter.revealDocumentsInFinder(documentIDs)
    }

    func stopWatchingSidebarFolders(_ documentIDs: Set<UUID>) {
        sidebarActionRouter.stopWatchingFolders(documentIDs)
    }

    func closeOtherSidebarDocuments(keeping documentIDs: Set<UUID>) {
        sidebarActionRouter.closeOtherDocuments(keeping: documentIDs)
    }

    func closeSelectedSidebarDocuments(_ documentIDs: Set<UUID>) {
        sidebarActionRouter.closeSelectedDocuments(documentIDs)
    }

    func closeAllSidebarDocuments() {
        sidebarActionRouter.closeAllDocuments()
    }

    func toggleSidebarPlacement(currentMultiFileDisplayMode: ReaderMultiFileDisplayMode) {
        sidebarActionRouter.toggleSidebarPlacement(currentMultiFileDisplayMode: currentMultiFileDisplayMode)
    }

    @discardableResult
    func updateFolderWatchExclusions(_ newExcludedPaths: [String]) -> Bool {
        let result = folderWatchFlowController?.updateFolderWatchExclusions(newExcludedPaths) ?? false
        refreshWindowPresentation()
        return result
    }

    // MARK: - Warning Flow

    func confirmFolderWatch(_ options: FolderWatchOptions) {
        let deactivated = folderWatchFlowController?.confirmFolderWatch(options) ?? false
        if deactivated {
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
        refreshWindowPresentation()
    }

    func stopFolderWatch() {
        folderWatchFlowController?.stopFolderWatchSession()
        sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        refreshWindowPresentation()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: FolderWatchAutoOpenWarning?) {
        folderWatchFlowController?.handleAutoOpenWarningChangeForWindow(warning, hostWindow: hostWindow)
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        folderWatchFlowController?.refreshAutoOpenWarningPresentationForWindow(hostWindow: hostWindow)
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        folderWatchFlowController?.openSelectedAutoOpenFilesAndRefresh()
        refreshWindowPresentation()
    }

    // MARK: - Action Dispatch

    func handleContentViewAction(_ action: ContentViewAction) {
        contentViewActionRouter.handle(action)
    }

    // MARK: - Appearance Lock

    func toggleAppearanceLock() {
        appearanceLockCoordinator.toggleLock()
    }

    func reapplyAppearance() {
        appearanceLockCoordinator.reapplyAcrossOpenDocuments()
    }

    func renderSelectedDocumentIfNeeded() {
        appearanceLockCoordinator.renderSelectedDocumentIfNeeded()
    }
}
