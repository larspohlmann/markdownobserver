import Foundation

/// Routes favorite-watched-folder and recent-history actions, plus the
/// edit-favorites flag.
@MainActor
final class FavoriteActionRouter {
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let recentHistoryCoordinatorProvider: () -> RecentHistoryCoordinator?
    private let settingsStore: SettingsStore
    private let fileOpenCoordinator: FileOpenCoordinator
    private let folderWatchFlowControllerProvider: () -> FolderWatchFlowController?
    private let callbacks: FavoriteRouterCallbacks

    init(
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        recentHistoryCoordinatorProvider: @escaping () -> RecentHistoryCoordinator?,
        settingsStore: SettingsStore,
        fileOpenCoordinator: FileOpenCoordinator,
        folderWatchFlowControllerProvider: @escaping () -> FolderWatchFlowController?,
        callbacks: FavoriteRouterCallbacks
    ) {
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.recentHistoryCoordinatorProvider = recentHistoryCoordinatorProvider
        self.settingsStore = settingsStore
        self.fileOpenCoordinator = fileOpenCoordinator
        self.folderWatchFlowControllerProvider = folderWatchFlowControllerProvider
        self.callbacks = callbacks
    }

    func saveFolderWatchAsFavorite(name: String) {
        favoriteWorkspaceControllerProvider()?.saveAsFavorite(
            name: name,
            currentSidebarWidth: callbacks.sidebarWidthProvider()
        )
    }

    func removeCurrentWatchFromFavorites() {
        favoriteWorkspaceControllerProvider()?.removeFromFavorites()
    }

    func startFavoriteWatch(_ favorite: FavoriteWatchedFolder) {
        callbacks.startFavoriteWatch(favorite)
    }

    func clearFavoriteWatchedFolders() {
        favoriteWorkspaceControllerProvider()?.clearAll()
    }

    func renameFavoriteWatchedFolder(id: UUID, name: String) {
        settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
    }

    func removeFavoriteWatchedFolder(id: UUID) {
        settingsStore.removeFavoriteWatchedFolder(id: id)
    }

    func reorderFavoriteWatchedFolders(orderedIDs: [UUID]) {
        settingsStore.reorderFavoriteWatchedFolders(orderedIDs: orderedIDs)
    }

    func startRecentManuallyOpenedFile(_ entry: RecentOpenedFile) {
        recentHistoryCoordinatorProvider()?.openRecentFile(
            entry,
            using: fileOpenCoordinator,
            session: folderWatchFlowControllerProvider()?.sharedFolderWatchSession
        )
        callbacks.applyTitlePresentation()
    }

    func startRecentFolderWatch(_ entry: RecentWatchedFolder) {
        recentHistoryCoordinatorProvider()?.startRecentFolderWatch(entry)
    }

    func clearRecentWatchedFolders() {
        recentHistoryCoordinatorProvider()?.clearRecentWatchedFolders()
    }

    func clearRecentManuallyOpenedFiles() {
        recentHistoryCoordinatorProvider()?.clearRecentManuallyOpenedFiles()
    }

    func editFavoriteWatchedFolders() {
        callbacks.setEditingFavorites(true)
    }

    func dismissEditFavorites() {
        callbacks.setEditingFavorites(false)
    }
}
