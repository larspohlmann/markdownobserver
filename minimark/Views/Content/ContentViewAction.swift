import Foundation

enum ContentViewAction {
    case requestFileOpen(FileOpenRequest)
    case requestFolderWatch(URL)
    case confirmFolderWatch(ReaderFolderWatchOptions)
    case cancelFolderWatch
    case stopFolderWatch
    case saveFolderWatchAsFavorite(String)
    case removeCurrentWatchFromFavorites
    case toggleAppearanceLock
    case startFavoriteWatch(ReaderFavoriteWatchedFolder)
    case clearFavoriteWatchedFolders
    case renameFavoriteWatchedFolder(id: UUID, name: String)
    case removeFavoriteWatchedFolder(UUID)
    case reorderFavoriteWatchedFolders([UUID])
    case startRecentManuallyOpenedFile(ReaderRecentOpenedFile)
    case startRecentFolderWatch(ReaderRecentWatchedFolder)
    case clearRecentWatchedFolders
    case clearRecentManuallyOpenedFiles
    case editSubfolders
}
