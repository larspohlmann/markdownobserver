import Foundation

/// Thin composite over three focused routers: `DocumentActionRouter`,
/// `FolderWatchActionRouter`, `FavoriteActionRouter`. Each inbound action is
/// switched on by case and dispatched to the matching sub-router method.
@MainActor
final class ContentViewActionRouter {
    private let document: DocumentActionRouter
    private let folderWatch: FolderWatchActionRouter
    private let favorite: FavoriteActionRouter

    init(
        document: DocumentActionRouter,
        folderWatch: FolderWatchActionRouter,
        favorite: FavoriteActionRouter
    ) {
        self.document = document
        self.folderWatch = folderWatch
        self.favorite = favorite
    }

    func handle(_ action: ContentViewAction) {
        switch action {
        case .requestFileOpen(let request):
            document.requestFileOpen(request)
        case .requestFolderWatch(let url):
            folderWatch.requestFolderWatch(url)
        case .confirmFolderWatch(let options):
            folderWatch.confirmFolderWatch(options)
        case .cancelFolderWatch:
            folderWatch.cancelFolderWatch()
        case .stopFolderWatch:
            folderWatch.stopFolderWatch()
        case .saveFolderWatchAsFavorite(let name):
            favorite.saveFolderWatchAsFavorite(name: name)
        case .removeCurrentWatchFromFavorites:
            favorite.removeCurrentWatchFromFavorites()
        case .toggleAppearanceLock:
            document.toggleAppearanceLock()
        case .startFavoriteWatch(let fav):
            favorite.startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders:
            favorite.clearFavoriteWatchedFolders()
        case .renameFavoriteWatchedFolder(let id, let name):
            favorite.renameFavoriteWatchedFolder(id: id, name: name)
        case .removeFavoriteWatchedFolder(let id):
            favorite.removeFavoriteWatchedFolder(id: id)
        case .reorderFavoriteWatchedFolders(let ids):
            favorite.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .startRecentManuallyOpenedFile(let entry):
            favorite.startRecentManuallyOpenedFile(entry)
        case .startRecentFolderWatch(let entry):
            favorite.startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders:
            favorite.clearRecentWatchedFolders()
        case .clearRecentManuallyOpenedFiles:
            favorite.clearRecentManuallyOpenedFiles()
        case .editSubfolders:
            folderWatch.editSubfolders()
        case .saveSourceDraft:
            document.saveSourceDraft()
        case .discardSourceDraft:
            document.discardSourceDraft()
        case .startSourceEditing:
            document.startSourceEditing()
        case .updateSourceDraft(let markdown):
            document.updateSourceDraft(markdown)
        case .grantImageDirectoryAccess(let url):
            document.grantImageDirectoryAccess(url)
        case .openInApplication(let app):
            document.openInApplication(app)
        case .revealInFinder:
            document.revealInFinder()
        case .presentError(let error):
            document.presentError(error)
        case .updateTOCHeadings(let headings):
            document.updateTOCHeadings(headings)
        }
    }

    func handle(_ action: FolderWatchToolbarAction) {
        switch action {
        case .activate:
            break // Handled by view (requires modal panel)
        case .startFavoriteWatch(let fav):
            favorite.startFavoriteWatch(fav)
        case .startRecentFolderWatch(let recent):
            favorite.startRecentFolderWatch(recent)
        case .editFavoriteWatchedFolders:
            favorite.editFavoriteWatchedFolders()
        case .clearRecentWatchedFolders:
            favorite.clearRecentWatchedFolders()
        }
    }

    func handle(_ action: EditFavoritesAction) {
        switch action {
        case .rename(let id, let name):
            favorite.renameFavoriteWatchedFolder(id: id, name: name)
        case .delete(let id):
            favorite.removeFavoriteWatchedFolder(id: id)
        case .reorder(let ids):
            favorite.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .dismiss:
            favorite.dismissEditFavorites()
        }
    }
}
