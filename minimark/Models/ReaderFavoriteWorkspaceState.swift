import Foundation

nonisolated struct ReaderFavoriteWorkspaceState: Equatable, Hashable, Codable, Sendable {
    static let defaultSidebarWidth: CGFloat = 250

    var fileSortMode: ReaderSidebarSortMode
    var groupSortMode: ReaderSidebarSortMode
    var sidebarPosition: ReaderMultiFileDisplayMode
    var sidebarWidth: CGFloat
    var pinnedGroupIDs: Set<String>
    var collapsedGroupIDs: Set<String>
    var lockedAppearance: LockedAppearance?

    static func from(
        settings: ReaderSettings,
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        sidebarWidth: CGFloat
    ) -> ReaderFavoriteWorkspaceState {
        ReaderFavoriteWorkspaceState(
            fileSortMode: settings.sidebarSortMode,
            groupSortMode: settings.sidebarGroupSortMode,
            sidebarPosition: settings.multiFileDisplayMode,
            sidebarWidth: sidebarWidth,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs
        )
    }
}
