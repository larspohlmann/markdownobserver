import Foundation

struct ContentViewCallbacks {
    let onRequestFileOpen: (FileOpenRequest) -> Void
    let onRequestFolderWatch: (URL) -> Void
    let onConfirmFolderWatch: (ReaderFolderWatchOptions) -> Void
    let onCancelFolderWatch: () -> Void
    let onStopFolderWatch: () -> Void
    let onSaveFolderWatchAsFavorite: (String) -> Void
    let onRemoveCurrentWatchFromFavorites: () -> Void
    let onToggleAppearanceLock: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onClearFavoriteWatchedFolders: () -> Void
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onReorderFavoriteWatchedFolders: ([UUID]) -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void
}
