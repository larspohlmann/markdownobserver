import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class WindowCoordinator {
    private let settingsStore: SettingsStore
    private let sidebarDocumentController: SidebarDocumentController
    private(set) var folderWatchOpen: WindowFolderWatchOpenController!
    private(set) var shell: WindowShellController!
    private(set) var documentOpen: WindowDocumentOpenCoordinator!
    private(set) var sidebarActions: SidebarDocumentActionRouter!
    private(set) var appearanceLock: AppearanceLockCoordinator!
    private(set) var contentActions: ContentViewActionRouter!
    private(set) var sidebarMetrics: WindowSidebarMetricsController!
    private(set) var folderWatchSession: WindowFolderWatchSessionFlow!
    private(set) var events: WindowEventBridge!

    // Window presentation state
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var isTitlebarEditingFavorites = false
    var isEditingSubfolders = false

    // Controller references (set via configure())
    private var appearanceController: WindowAppearanceController?
    private var groupStateController: SidebarGroupStateController?
    private var favoriteWorkspaceController: FavoriteWorkspaceController?
    private var folderWatchFlowController: FolderWatchFlowController?
    private var uiTestLaunchCoordinator: UITestLaunchCoordinator?
    private var recentHistoryCoordinator: RecentHistoryCoordinator?

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
        settingsStore: SettingsStore,
        sidebarDocumentController: SidebarDocumentController
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
            callbacks: WindowOpenCallbacks(
                applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
                refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() },
                prepareRecentFolderWatch: { [weak self] folderURL, options in
                    self?.folderWatchFlowController?.presentOptions(for: folderURL, options: options)
                }
            )
        )
        self.sidebarActions = SidebarDocumentActionRouter(
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            sidebarWidthProvider: { [weak self] in self?.sidebarMetrics.width ?? SidebarWorkspaceMetrics.sidebarIdealWidth },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.appearanceLock = AppearanceLockCoordinator(
            appearanceControllerProvider: { [weak self] in self?.appearanceController },
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController }
        )
        self.sidebarMetrics = WindowSidebarMetricsController(
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            hostWindowProvider: { [weak self] in self?.shell.hostWindow }
        )
        self.folderWatchSession = WindowFolderWatchSessionFlow(
            folderWatchFlowControllerProvider: { [weak self] in self?.folderWatchFlowController },
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            sidebarMetrics: sidebarMetrics,
            hostWindowProvider: { [weak self] in self?.shell.hostWindow },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.events = WindowEventBridge(
            shell: shell,
            folderWatchOpen: folderWatchOpen,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            groupStateControllerProvider: { [weak self] in self?.groupStateController },
            favoriteWorkspaceControllerProvider: { [weak self] in self?.favoriteWorkspaceController },
            appearanceControllerProvider: { [weak self] in self?.appearanceController },
            uiTestLaunchCoordinatorProvider: { [weak self] in self?.uiTestLaunchCoordinator },
            refreshWindowShellState: { [weak self] in self?.refreshWindowShellState() }
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
            sidebarWidthProvider: { [weak self] in self?.sidebarMetrics.width ?? SidebarWorkspaceMetrics.sidebarIdealWidth },
            applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
            confirmFolderWatch: { [weak self] options in self?.folderWatchSession.confirm(options) },
            stopFolderWatch: { [weak self] in self?.folderWatchSession.stop() },
            startFavoriteWatch: { [weak self] favorite in self?.folderWatchSession.startFavoriteWatch(favorite) },
            setEditingSubfolders: { [weak self] value in self?.isEditingSubfolders = value },
            setEditingFavorites: { [weak self] value in self?.isTitlebarEditingFavorites = value }
        )
    }

    // MARK: - Composite refresh

    private func refreshSharedFolderWatchState() {
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

}
