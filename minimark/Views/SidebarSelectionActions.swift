import Foundation

/// Bundles the per-row / selection-wide action closures that `WindowRootView`
/// hands to `SidebarWorkspaceView` and its children. Always constructed together;
/// always consumed by the same sidebar selection subview, so a named value type
/// is more honest than threading each closure as a separate parameter.
struct SidebarSelectionActions {
    let openInDefaultApp: (Set<UUID>) -> Void
    let openInApplication: (ExternalApplication, Set<UUID>) -> Void
    let revealInFinder: (Set<UUID>) -> Void
    let stopWatchingFolders: (Set<UUID>) -> Void
    let closeDocuments: (Set<UUID>) -> Void
    let closeOtherDocuments: (Set<UUID>) -> Void
    let closeAll: () -> Void
}
