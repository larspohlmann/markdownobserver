import Foundation

/// Window-scoped callbacks threaded into `FavoriteActionRouter`. Always
/// constructed together at `WindowCoordinator`.
@MainActor
struct FavoriteRouterCallbacks {
    let startFavoriteWatch: (FavoriteWatchedFolder) -> Void
    let applyTitlePresentation: () -> Void
    let sidebarWidthProvider: () -> CGFloat
    let setEditingFavorites: (Bool) -> Void
}
