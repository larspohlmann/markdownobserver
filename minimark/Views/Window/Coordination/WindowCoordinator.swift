import AppKit
import Foundation
import Observation

@MainActor
struct WindowCoordinatorDependencies {
    let appearanceController: @MainActor () -> WindowAppearanceController?
    let groupStateController: @MainActor () -> SidebarGroupStateController?
    let favoriteWorkspaceController: @MainActor () -> FavoriteWorkspaceController?
    let folderWatchFlowController: @MainActor () -> FolderWatchFlowController?
    let uiTestLaunchCoordinator: @MainActor () -> UITestLaunchCoordinator?
    let recentHistoryCoordinator: @MainActor () -> RecentHistoryCoordinator?
}

@MainActor
@Observable
final class WindowCoordinator {
    private let settingsStore: SettingsStore
    private let sidebarDocumentController: SidebarDocumentController
    private let dependencies: WindowCoordinatorDependencies
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

    init(
        settingsStore: SettingsStore,
        sidebarDocumentController: SidebarDocumentController,
        dependencies: WindowCoordinatorDependencies
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
        self.dependencies = dependencies
        self.shell = WindowShellController(
            sidebarDocumentController: sidebarDocumentController,
            folderWatchSessionProvider: { [weak self] in
                self?.dependencies.folderWatchFlowController()?.sharedFolderWatchSession
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
                self?.dependencies.folderWatchFlowController()?.sharedFolderWatchSession
            },
            callbacks: WindowOpenCallbacks(
                applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
                refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() },
                prepareRecentFolderWatch: { [weak self] folderURL, options in
                    self?.dependencies.folderWatchFlowController()?.presentOptions(for: folderURL, options: options)
                }
            )
        )
        self.sidebarActions = SidebarDocumentActionRouter(
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
            sidebarWidthProvider: { [weak self] in self?.sidebarMetrics.width ?? SidebarWorkspaceMetrics.sidebarIdealWidth },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.appearanceLock = AppearanceLockCoordinator(
            appearanceControllerProvider: { [weak self] in self?.dependencies.appearanceController() },
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() }
        )
        self.sidebarMetrics = WindowSidebarMetricsController(
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
            hostWindowProvider: { [weak self] in self?.shell.hostWindow }
        )
        self.folderWatchSession = WindowFolderWatchSessionFlow(
            folderWatchFlowControllerProvider: { [weak self] in self?.dependencies.folderWatchFlowController() },
            favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
            sidebarMetrics: sidebarMetrics,
            hostWindowProvider: { [weak self] in self?.shell.hostWindow },
            refreshWindowPresentation: { [weak self] in self?.refreshWindowPresentation() }
        )
        self.events = WindowEventBridge(
            hostLifecycle: WindowHostLifecycleDispatcher(
                shell: shell,
                folderWatchOpen: folderWatchOpen,
                uiTestLaunchCoordinatorProvider: { [weak self] in self?.dependencies.uiTestLaunchCoordinator() },
                refreshWindowShellState: { [weak self] in self?.refreshWindowShellState() }
            ),
            documentSync: WindowDocumentSyncDispatcher(
                shell: shell,
                sidebarDocumentController: sidebarDocumentController,
                settingsStore: settingsStore,
                groupStateControllerProvider: { [weak self] in self?.dependencies.groupStateController() }
            ),
            favoriteWorkspace: FavoriteWorkspaceEventDispatcher(
                favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
                appearanceControllerProvider: { [weak self] in self?.dependencies.appearanceController() },
                settingsStore: settingsStore
            ),
            groupState: GroupStateEventDispatcher(
                favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
                settingsStore: settingsStore
            )
        )
        self.contentActions = ContentViewActionRouter(
            document: DocumentActionRouter(
                documentOpen: documentOpen,
                appearanceLock: appearanceLock,
                sidebarDocumentController: sidebarDocumentController
            ),
            folderWatch: FolderWatchActionRouter(
                folderWatchFlowControllerProvider: { [weak self] in self?.dependencies.folderWatchFlowController() },
                callbacks: FolderWatchRouterCallbacks(
                    confirmFolderWatch: { [weak self] options in self?.folderWatchSession.confirm(options) },
                    stopFolderWatch: { [weak self] in self?.folderWatchSession.stop() },
                    setEditingSubfolders: { [weak self] value in self?.isEditingSubfolders = value }
                )
            ),
            favorite: FavoriteActionRouter(
                favoriteWorkspaceControllerProvider: { [weak self] in self?.dependencies.favoriteWorkspaceController() },
                recentHistoryCoordinatorProvider: { [weak self] in self?.dependencies.recentHistoryCoordinator() },
                settingsStore: settingsStore,
                fileOpenCoordinator: sidebarDocumentController.fileOpenCoordinator,
                folderWatchFlowControllerProvider: { [weak self] in self?.dependencies.folderWatchFlowController() },
                callbacks: FavoriteRouterCallbacks(
                    startFavoriteWatch: { [weak self] favorite in self?.folderWatchSession.startFavoriteWatch(favorite) },
                    applyTitlePresentation: { [weak self] in self?.shell.applyTitlePresentation() },
                    sidebarWidthProvider: { [weak self] in self?.sidebarMetrics.width ?? SidebarWorkspaceMetrics.sidebarIdealWidth },
                    setEditingFavorites: { [weak self] value in self?.isTitlebarEditingFavorites = value }
                )
            )
        )
        documentOpen.configureStoreCallbacks(
            lockedAppearanceProvider: { [dependencies] in dependencies.appearanceController()?.lockedAppearance }
        )
    }

    // MARK: - Composite refresh

    private func refreshSharedFolderWatchState() {
        dependencies.folderWatchFlowController()?.refreshSharedState()
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
