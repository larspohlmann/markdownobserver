import Foundation

struct ContentViewFolderWatchState {
    let activeFolderWatch: ReaderFolderWatchSession?
    let isFolderWatchInitialScanInProgress: Bool
    let isFolderWatchInitialScanFailed: Bool
    let canStopFolderWatch: Bool
    let pendingFolderWatchURL: URL?
    let isCurrentWatchAFavorite: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let isAppearanceLocked: Bool
    let effectiveReaderTheme: ReaderThemeKind
}
