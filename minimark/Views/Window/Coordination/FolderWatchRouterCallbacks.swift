import Foundation

/// Window-scoped callbacks threaded into `FolderWatchActionRouter`. Always
/// constructed together at `WindowCoordinator`.
@MainActor
struct FolderWatchRouterCallbacks {
    let confirmFolderWatch: (FolderWatchOptions) -> Void
    let stopFolderWatch: () -> Void
    let setEditingSubfolders: (Bool) -> Void
}
