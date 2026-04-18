import Foundation

/// Callbacks the window asks the document-open coordinator to invoke after
/// each kind of open. Always constructed together at `WindowCoordinator`.
@MainActor
struct WindowOpenCallbacks {
    let applyTitlePresentation: () -> Void
    let refreshWindowPresentation: () -> Void
    let prepareRecentFolderWatch: (URL, FolderWatchOptions) -> Void
}
