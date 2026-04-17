import Foundation

/// Reduces three action enums (`ContentViewAction`, `FolderWatchToolbarAction`,
/// `EditFavoritesAction`) by dispatching each case to the appropriate
/// collaborator. Holds no state of its own — every case forwards to one of the
/// extracted controllers, the settings store, or one of the composite
/// callbacks that the window coordinator owns (folder-watch confirm/stop,
/// favorite watch start, sidebar-flag toggles).
@MainActor
final class ContentViewActionRouter {
    private let documentOpen: WindowDocumentOpenCoordinator
    private let appearanceLock: AppearanceLockCoordinator
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let settingsStore: ReaderSettingsStore
    private let folderWatchFlowControllerProvider: () -> FolderWatchFlowController?
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let recentHistoryCoordinatorProvider: () -> RecentHistoryCoordinator?
    private let fileOpenCoordinator: FileOpenCoordinator
    private let sidebarWidthProvider: () -> CGFloat
    private let applyTitlePresentation: () -> Void
    private let confirmFolderWatch: (FolderWatchOptions) -> Void
    private let stopFolderWatch: () -> Void
    private let startFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    private let setEditingSubfolders: (Bool) -> Void
    private let setEditingFavorites: (Bool) -> Void

    init(
        documentOpen: WindowDocumentOpenCoordinator,
        appearanceLock: AppearanceLockCoordinator,
        sidebarDocumentController: ReaderSidebarDocumentController,
        settingsStore: ReaderSettingsStore,
        folderWatchFlowControllerProvider: @escaping () -> FolderWatchFlowController?,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        recentHistoryCoordinatorProvider: @escaping () -> RecentHistoryCoordinator?,
        fileOpenCoordinator: FileOpenCoordinator,
        sidebarWidthProvider: @escaping () -> CGFloat,
        applyTitlePresentation: @escaping () -> Void,
        confirmFolderWatch: @escaping (FolderWatchOptions) -> Void,
        stopFolderWatch: @escaping () -> Void,
        startFavoriteWatch: @escaping (ReaderFavoriteWatchedFolder) -> Void,
        setEditingSubfolders: @escaping (Bool) -> Void,
        setEditingFavorites: @escaping (Bool) -> Void
    ) {
        self.documentOpen = documentOpen
        self.appearanceLock = appearanceLock
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.folderWatchFlowControllerProvider = folderWatchFlowControllerProvider
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.recentHistoryCoordinatorProvider = recentHistoryCoordinatorProvider
        self.fileOpenCoordinator = fileOpenCoordinator
        self.sidebarWidthProvider = sidebarWidthProvider
        self.applyTitlePresentation = applyTitlePresentation
        self.confirmFolderWatch = confirmFolderWatch
        self.stopFolderWatch = stopFolderWatch
        self.startFavoriteWatch = startFavoriteWatch
        self.setEditingSubfolders = setEditingSubfolders
        self.setEditingFavorites = setEditingFavorites
    }

    func handle(_ action: ContentViewAction) {
        switch action {
        case .requestFileOpen(let request):
            documentOpen.openFileRequest(request)
        case .requestFolderWatch(let url):
            folderWatchFlowControllerProvider()?.prepareOptions(for: url)
        case .confirmFolderWatch(let options):
            confirmFolderWatch(options)
        case .cancelFolderWatch:
            folderWatchFlowControllerProvider()?.cancelPendingWatch()
        case .stopFolderWatch:
            stopFolderWatch()
        case .saveFolderWatchAsFavorite(let name):
            favoriteWorkspaceControllerProvider()?.saveAsFavorite(name: name, currentSidebarWidth: sidebarWidthProvider())
        case .removeCurrentWatchFromFavorites:
            favoriteWorkspaceControllerProvider()?.removeFromFavorites()
        case .toggleAppearanceLock:
            appearanceLock.toggleLock()
        case .startFavoriteWatch(let fav):
            startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders:
            favoriteWorkspaceControllerProvider()?.clearAll()
        case .renameFavoriteWatchedFolder(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .removeFavoriteWatchedFolder(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorderFavoriteWatchedFolders(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .startRecentManuallyOpenedFile(let entry):
            recentHistoryCoordinatorProvider()?.openRecentFile(
                entry,
                using: fileOpenCoordinator,
                session: folderWatchFlowControllerProvider()?.sharedFolderWatchSession
            )
            applyTitlePresentation()
        case .startRecentFolderWatch(let entry):
            recentHistoryCoordinatorProvider()?.startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders:
            recentHistoryCoordinatorProvider()?.clearRecentWatchedFolders()
        case .clearRecentManuallyOpenedFiles:
            recentHistoryCoordinatorProvider()?.clearRecentManuallyOpenedFiles()
        case .editSubfolders:
            setEditingSubfolders(true)
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

    func handle(_ action: FolderWatchToolbarAction) {
        switch action {
        case .activate:
            break // Handled by view (requires modal panel)
        case .startFavoriteWatch(let favorite):
            startFavoriteWatch(favorite)
        case .startRecentFolderWatch(let recent):
            recentHistoryCoordinatorProvider()?.startRecentFolderWatch(recent)
        case .editFavoriteWatchedFolders:
            setEditingFavorites(true)
        case .clearRecentWatchedFolders:
            recentHistoryCoordinatorProvider()?.clearRecentWatchedFolders()
        }
    }

    func handle(_ action: EditFavoritesAction) {
        switch action {
        case .rename(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .delete(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorder(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .dismiss:
            setEditingFavorites(false)
        }
    }
}
