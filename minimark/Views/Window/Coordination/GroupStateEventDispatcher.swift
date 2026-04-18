/// Persists sidebar group state changes. Routes group/pinning/sort mutations
/// to either the active favorite workspace (when one is active) or the
/// settings store (the default persistence target).
@MainActor
final class GroupStateEventDispatcher {
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let settingsStore: SettingsStore

    init(
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        settingsStore: SettingsStore
    ) {
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.settingsStore = settingsStore
    }

    func handleGroupStateChange(
        oldSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot,
        newSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot
    ) {
        if let favoriteController = favoriteWorkspaceControllerProvider(), favoriteController.isActive {
            let needsUpdate =
                favoriteController.activeFavoriteWorkspaceState?.pinnedGroupIDs != newSnapshot.pinnedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.collapsedGroupIDs != newSnapshot.collapsedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.groupSortMode != newSnapshot.sortMode ||
                favoriteController.activeFavoriteWorkspaceState?.fileSortMode != newSnapshot.fileSortMode ||
                favoriteController.activeFavoriteWorkspaceState?.manualGroupOrder != newSnapshot.manualGroupOrder

            if needsUpdate {
                favoriteController.updateGroupState(
                    pinnedGroupIDs: newSnapshot.pinnedGroupIDs,
                    collapsedGroupIDs: newSnapshot.collapsedGroupIDs,
                    groupSortMode: newSnapshot.sortMode,
                    fileSortMode: newSnapshot.fileSortMode,
                    manualGroupOrder: newSnapshot.manualGroupOrder
                )
            }
        } else {
            if oldSnapshot.sortMode != newSnapshot.sortMode {
                settingsStore.updateSidebarGroupSortMode(newSnapshot.sortMode)
            }
            if oldSnapshot.fileSortMode != newSnapshot.fileSortMode {
                settingsStore.updateSidebarSortMode(newSnapshot.fileSortMode)
            }
        }
    }
}
