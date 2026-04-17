import Foundation
import Testing
@testable import minimark

@Suite
struct SettingsStoreFavoritesTests {
    @Test @MainActor func updateFavoriteWorkspaceStatePersistsChanges() {
        let store = TestSettingsStore(autoRefreshOnExternalChange: false)
        let folderURL = URL(fileURLWithPath: "/tmp/test")
        let options = FolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: options
        )

        let favoriteID = store.currentSettings.favoriteWatchedFolders.first!.id
        let newState = FavoriteWorkspaceState(
            fileSortMode: .nameDescending,
            groupSortMode: .nameAscending,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 400,
            pinnedGroupIDs: ["pinned"],
            collapsedGroupIDs: ["collapsed"]
        )

        store.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: newState)

        let updated = store.currentSettings.favoriteWatchedFolders.first!
        #expect(updated.workspaceState == newState)
    }

    @Test @MainActor func updateFavoriteWorkspaceStateNoOpForUnknownID() {
        let store = TestSettingsStore(autoRefreshOnExternalChange: false)
        let folderURL = URL(fileURLWithPath: "/tmp/test")
        let options = FolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: options
        )

        let before = store.currentSettings.favoriteWatchedFolders
        store.updateFavoriteWorkspaceState(
            id: UUID(),
            workspaceState: FavoriteWorkspaceState(
                fileSortMode: .nameDescending,
                groupSortMode: .nameAscending,
                sidebarPosition: .sidebarRight,
                sidebarWidth: 400,
                pinnedGroupIDs: [],
                collapsedGroupIDs: []
            )
        )

        #expect(store.currentSettings.favoriteWatchedFolders == before)
    }
}
