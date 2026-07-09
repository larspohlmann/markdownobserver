import Foundation

struct ContentViewFolderWatchState: Equatable {
    let activeFolderWatch: FolderWatchSession?
    let isFolderWatchInitialScanInProgress: Bool
    let isFolderWatchInitialScanFailed: Bool
    let canStopFolderWatch: Bool
    let pendingFolderWatchURL: URL?
    let isCurrentWatchAFavorite: Bool
    let favoriteWatchedFolders: [FavoriteWatchedFolder]
    let recentWatchedFolders: [RecentWatchedFolder]
    let recentManuallyOpenedFiles: [RecentOpenedFile]
    let isAppearanceLocked: Bool
    let effectiveReaderTheme: ThemeKind
    let effectiveReaderThemeOverride: ThemeOverride?
}
