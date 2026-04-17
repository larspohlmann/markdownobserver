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

    private var fileOpenCoordinator: FileOpenCoordinator {
        sidebarDocumentController.fileOpenCoordinator
    }

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
        switch action {
        case .activate:
            break // Handled by view (requires modal panel)
        case .startFavoriteWatch(let favorite):
            startFavoriteWatch(favorite)
        case .startRecentFolderWatch(let recent):
            recentHistoryCoordinator?.startRecentFolderWatch(recent)
        case .editFavoriteWatchedFolders:
            isTitlebarEditingFavorites = true
        case .clearRecentWatchedFolders:
            recentHistoryCoordinator?.clearRecentWatchedFolders()
        }
    }

    func handleEditFavoritesAction(_ action: EditFavoritesAction) {
        switch action {
        case .rename(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .delete(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorder(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .dismiss:
            isTitlebarEditingFavorites = false
        }
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
        switch action {
        case .requestFileOpen(let request):
            fileOpenCoordinator.open(request)
            refreshWindowPresentation()
        case .requestFolderWatch(let url):
            folderWatchFlowController?.prepareOptions(for: url)
        case .confirmFolderWatch(let options):
            confirmFolderWatch(options)
        case .cancelFolderWatch:
            folderWatchFlowController?.cancelPendingWatch()
        case .stopFolderWatch:
            stopFolderWatch()
        case .saveFolderWatchAsFavorite(let name):
            favoriteWorkspaceController?.saveAsFavorite(name: name, currentSidebarWidth: sidebarWidth)
        case .removeCurrentWatchFromFavorites:
            favoriteWorkspaceController?.removeFromFavorites()
        case .toggleAppearanceLock:
            toggleAppearanceLock()
        case .startFavoriteWatch(let fav):
            startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders:
            favoriteWorkspaceController?.clearAll()
        case .renameFavoriteWatchedFolder(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .removeFavoriteWatchedFolder(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorderFavoriteWatchedFolders(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .startRecentManuallyOpenedFile(let entry):
            recentHistoryCoordinator?.openRecentFile(entry, using: fileOpenCoordinator, session: folderWatchFlowController?.sharedFolderWatchSession)
            applyWindowTitlePresentation()
        case .startRecentFolderWatch(let entry):
            recentHistoryCoordinator?.startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders:
            recentHistoryCoordinator?.clearRecentWatchedFolders()
        case .clearRecentManuallyOpenedFiles:
            recentHistoryCoordinator?.clearRecentManuallyOpenedFiles()
        case .editSubfolders:
            isEditingSubfolders = true
        case .saveSourceDraft:
            sidebarDocumentController.selectedReaderStore.saveSourceDraft()
        case .discardSourceDraft:
            sidebarDocumentController.selectedReaderStore.discardSourceDraft()
        case .startSourceEditing:
            sidebarDocumentController.selectedReaderStore.startEditingSource()
        case .updateSourceDraft(let markdown):
            sidebarDocumentController.selectedReaderStore.updateSourceDraft(markdown)
        case .grantImageDirectoryAccess(let url):
            sidebarDocumentController.selectedReaderStore.grantImageDirectoryAccess(folderURL: url)
        case .openInApplication(let app):
            sidebarDocumentController.selectedReaderStore.document.openInApplication(app)
        case .revealInFinder:
            sidebarDocumentController.selectedReaderStore.document.revealInFinder()
        case .presentError(let error):
            sidebarDocumentController.selectedReaderStore.handle(error)
        case .updateTOCHeadings(let headings):
            sidebarDocumentController.selectedReaderStore.toc.updateHeadings(headings)
        }
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
