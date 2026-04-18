import Foundation

struct WatchPillState {
    let activeFolderWatch: FolderWatchSession?
    let isCurrentWatchAFavorite: Bool
    let canStop: Bool
    let isAppearanceLocked: Bool
}
