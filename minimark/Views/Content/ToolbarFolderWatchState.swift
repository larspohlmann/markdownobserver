struct ToolbarFolderWatchState: Equatable {
    let activeFolderWatch: FolderWatchSession?
    let isInitialScanInProgress: Bool
    let didInitialScanFail: Bool
    let favoriteWatchedFolders: [FavoriteWatchedFolder]
    let recentWatchedFolders: [RecentWatchedFolder]
}
