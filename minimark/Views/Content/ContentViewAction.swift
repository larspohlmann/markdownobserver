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
    case saveSourceDraft
    case discardSourceDraft
    case startSourceEditing
    case updateSourceDraft(String)
    case grantImageDirectoryAccess(URL)
    case openInApplication(ReaderExternalApplication?)
    case revealInFinder
    case presentError(Error)
    case updateTOCHeadings([TOCHeading])
}
