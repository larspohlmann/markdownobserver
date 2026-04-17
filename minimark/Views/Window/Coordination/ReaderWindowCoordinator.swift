import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ReaderWindowCoordinator {
    private let settingsStore: ReaderSettingsStore
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private(set) var folderWatchOpen: WindowFolderWatchOpenController!
    private(set) var shell: WindowShellController!
    private(set) var documentOpen: WindowDocumentOpenCoordinator!
    private(set) var sidebarActions: SidebarDocumentActionRouter!
    private(set) var appearanceLock: AppearanceLockCoordinator!
    private(set) var contentActions: ContentViewActionRouter!
    let openDocumentPathTracker = OpenDocumentPathTracker()

    // Window presentation state
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    var lastAppliedSidebarDelta: CGFloat = 0
    var isTitlebarEditingFavorites = false
    var isEditingSubfolders = false

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
        documentOpen.configureStoreCallbacks(
            lockedAppearanceProvider: { [weak appearanceController] in appearanceController?.lockedAppearance }
        )
    }

    init(
        settingsStore: ReaderSettingsStore,
        sidebarDocumentController: ReaderSidebarDocumentController
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
        self.shell = WindowShellController(
            sidebarDocumentController: sidebarDocumentController,
            folderWatchSessionProvider: { [weak self] in
                self?.folderWatchFlowController?.sharedFolderWatchSession
            }
        )
        self.folderWatchOpen = WindowFolderWatchOpenController(
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            isHostWindowAttached: { [weak self] in self?.shell.hostWindow != nil },
            onAfterFlush: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.documentOpen = WindowDocumentOpenCoordinator(
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            folderWatchOpen: folderWatchOpen,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            folderWatchSessionProvider: { [weak self] in
                self?.folderWatchFlowController?.sharedFolderWatchSession
            },
            applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() },
            prepareRecentFolderWatch: { [weak self] folderURL, options in
                self?.folderWatchFlowController?.presentOptions(for: folderURL, options: options)
            }
        )
        self.sidebarActions = SidebarDocumentActionRouter(
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            sidebarWidthProvider: { [weak self] in self?.sidebarWidth ?? ReaderSidebarWorkspaceMetrics.sidebarIdealWidth },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.appearanceLock = AppearanceLockCoordinator(
            appearanceControllerProvider: { [weak self] in self?.appearanceController },
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController }
        )
        self.contentActions = ContentViewActionRouter(
            documentOpen: documentOpen,
            appearanceLock: appearanceLock,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            folderWatchFlowControllerProvider: { [weak self] in self?.folderWatchFlowController },
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            recentHistoryCoordinatorProvider: { [weak self] in self?.recentHistoryCoordinator },
            fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
            sidebarWidthProvider: { [weak self] in self?.sidebarWidth ?? ReaderSidebarWorkspaceMetrics.sidebarIdealWidth },
            applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
            confirmFolderWatch: { [weak self] options in self?.confirmFolderWatch(options) },
            stopFolderWatch: { [weak self] in self?.stopFolderWatch() },
            startFavoriteWatch: { [weak self] favorite in self?.startFavoriteWatch(favorite) },
            setEditingSubfolders: { [weak self] value in self?.isEditingSubfolders = value },
            setEditingFavorites: { [weak self] value in self?.isTitlebarEditingFavorites = value }
        )
    }

    // MARK: - Composite refresh

    func refreshSharedFolderWatchState() {
        folderWatchFlowController?.refreshSharedState()
    }

    func refreshWindowPresentation() {
        refreshSharedFolderWatchState()
        shell.applyTitlePresentation()
    }

    func refreshWindowShellState() {
        refreshSharedFolderWatchState()
        shell.refreshRegistrationAndTitle()
    }

    // MARK: - Window lifecycle

    func handleWindowAccessorUpdate(_ window: NSWindow?) {
        guard shell.updateHostWindow(window) else { return }
        handleHostWindowChange()
    }

    private func handleHostWindowChange() {
        refreshWindowShellState()
        uiTestLaunchCoordinator?.applyConfigurationIfNeeded()
        if shell.hostWindow != nil, folderWatchOpen.hasPendingEvents {
            folderWatchOpen.flush()
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
        shell.configureDockTile()
    }

    func handleWindowDisappear() {
        shell.clearDockTile()
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

        guard isSidebarVisible != wasVisible, let window = shell.hostWindow else {
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

    // MARK: - Composite folder-watch flows (mutate sidebarWidth + refresh)

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

    @discardableResult
    func updateFolderWatchExclusions(_ newExcludedPaths: [String]) -> Bool {
        let result = folderWatchFlowController?.updateFolderWatchExclusions(newExcludedPaths) ?? false
        refreshWindowPresentation()
        return result
    }

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
        folderWatchFlowController?.handleAutoOpenWarningChangeForWindow(warning, hostWindow: shell.hostWindow)
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        folderWatchFlowController?.refreshAutoOpenWarningPresentationForWindow(hostWindow: shell.hostWindow)
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        folderWatchFlowController?.openSelectedAutoOpenFilesAndRefresh()
        refreshWindowPresentation()
    }
}
