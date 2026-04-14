import Foundation
import Observation

@MainActor
@Observable
final class FavoriteWorkspaceController {
    private(set) var activeFavoriteID: UUID?
    private(set) var activeFavoriteWorkspaceState: ReaderFavoriteWorkspaceState?

    var isActive: Bool { activeFavoriteID != nil }

    func activate(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
        activeFavoriteID = id
        activeFavoriteWorkspaceState = workspaceState
    }

    func deactivate() {
        activeFavoriteID = nil
        activeFavoriteWorkspaceState = nil
    }

    func updateSidebarWidth(_ width: CGFloat) {
        activeFavoriteWorkspaceState?.sidebarWidth = width
    }

    func updateSidebarPosition(_ position: ReaderMultiFileDisplayMode) {
        activeFavoriteWorkspaceState?.sidebarPosition = position
    }

    func updateLockedAppearance(_ appearance: LockedAppearance?) {
        activeFavoriteWorkspaceState?.lockedAppearance = appearance
    }

    func updateGroupState(
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        groupSortMode: ReaderSidebarSortMode,
        fileSortMode: ReaderSidebarSortMode,
        manualGroupOrder: [String]?
    ) {
        activeFavoriteWorkspaceState?.pinnedGroupIDs = pinnedGroupIDs
        activeFavoriteWorkspaceState?.collapsedGroupIDs = collapsedGroupIDs
        activeFavoriteWorkspaceState?.groupSortMode = groupSortMode
        activeFavoriteWorkspaceState?.fileSortMode = fileSortMode
        activeFavoriteWorkspaceState?.manualGroupOrder = manualGroupOrder
    }

    func matchingFavorite(
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        in favorites: [ReaderFavoriteWatchedFolder]
    ) -> ReaderFavoriteWatchedFolder? {
        let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path
        return favorites.first { $0.matches(folderPath: normalizedPath, options: options) }
    }

    func persistFinalState(to settingsStore: some ReaderSettingsStoring) {
        guard let id = activeFavoriteID, let state = activeFavoriteWorkspaceState else { return }
        settingsStore.updateFavoriteWorkspaceState(id: id, workspaceState: state)
    }
}
