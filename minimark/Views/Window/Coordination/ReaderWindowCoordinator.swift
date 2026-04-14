import AppKit
import Foundation
import Observation

@MainActor
private struct ReaderWindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void

    func configure(_ store: ReaderStore) {
        if let lockedAppearance = lockedAppearanceProvider() {
            store.setAppearanceOverride(lockedAppearance)
        }
        store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, folderWatchSession, origin in
            onOpenAdditionalDocument(
                event.fileURL,
                folderWatchSession,
                origin,
                event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }
}

@MainActor
@Observable
final class ReaderWindowCoordinator {
    private let settingsStore: ReaderSettingsStore
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let folderWatchOpenCoordinator = ReaderFolderWatchOpenCoordinator()

    // Window presentation state (will be migrated from view @State)
    var hostWindow: NSWindow?
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    let dockTileWindowToken = UUID()
    var hasAppliedUITestLaunchConfiguration = false
    var uiTestWatchFlowTask: Task<Void, Never>?
    var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    var lastAppliedSidebarDelta: CGFloat = 0
    var isTitlebarEditingFavorites = false
    var isEditingSubfolders = false

    // Controller references (set via configure())
    private(set) var appearanceController: WindowAppearanceController?
    private(set) var groupStateController: SidebarGroupStateController?
    private(set) var favoriteWorkspaceController: FavoriteWorkspaceController?
    private(set) var folderWatchFlowController: FolderWatchFlowController?

    func configure(
        appearanceController: WindowAppearanceController,
        groupStateController: SidebarGroupStateController,
        favoriteWorkspaceController: FavoriteWorkspaceController,
        folderWatchFlowController: FolderWatchFlowController
    ) {
        self.appearanceController = appearanceController
        self.groupStateController = groupStateController
        self.favoriteWorkspaceController = favoriteWorkspaceController
        self.folderWatchFlowController = folderWatchFlowController
    }

    init(
        settingsStore: ReaderSettingsStore,
        sidebarDocumentController: ReaderSidebarDocumentController
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
    }

    var hasPendingFolderWatchOpenEvents: Bool {
        folderWatchOpenCoordinator.hasPendingEvents
    }

    func configureStoreCallbacks(
        lockedAppearanceProvider: @escaping @MainActor () -> LockedAppearance? = { nil },
        onOpenAdditionalDocument: @escaping (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void
    ) {
        sidebarDocumentController.setStoreConfigurator { store in
            ReaderWindowStoreCallbackConfigurator(
                lockedAppearanceProvider: lockedAppearanceProvider,
                onOpenAdditionalDocument: onOpenAdditionalDocument
            ).configure(store)
        }
    }

    func sharedFolderWatchState() -> (session: ReaderFolderWatchSession?, canStop: Bool) {
        (
            sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession,
            sidebarDocumentController.folderWatchCoordinator.canStopFolderWatch
        )
    }

    func resolveWindowTitle(activeFolderWatch: ReaderFolderWatchSession?) -> String {
        ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: sidebarDocumentController.selectedWindowTitle,
            activeFolderWatch: activeFolderWatch,
            hasUnacknowledgedExternalChange: sidebarDocumentController.selectedHasUnacknowledgedExternalChange
        )
    }

    func enqueueFolderWatchOpen(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin,
        onFlushRequested: @escaping @MainActor () -> Void
    ) {
        folderWatchOpenCoordinator.enqueue(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin,
            onFlushRequested: onFlushRequested
        )
    }

    func consumeQueuedFolderWatchOpenBatchIfPossible(
        canFlushImmediately: Bool,
        onFlushRequested: @escaping @MainActor () -> Void
    ) -> ReaderFolderWatchOpenBatch? {
        folderWatchOpenCoordinator.consumeBatchIfPossible(
            canFlushImmediately: canFlushImmediately,
            onFlushRequested: onFlushRequested
        )
    }

    func registerWindow(
        _ hostWindow: NSWindow?,
        activeFolderWatch: ReaderFolderWatchSession?
    ) {
        ReaderWindowRegistry.shared.registerWindow(
            hostWindow,
            focusDocument: { [sidebarDocumentController] fileURL in
                sidebarDocumentController.focusDocument(at: fileURL)
            },
            watchedFolderURLProvider: {
                activeFolderWatch?.folderURL
            }
        )
    }
}
