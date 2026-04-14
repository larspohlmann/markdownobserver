import Foundation
import Testing
@testable import minimark

@Suite
struct FavoriteWorkspaceControllerTests {
    @Test @MainActor func initialStateIsInactive() {
        let controller = FavoriteWorkspaceController()
        #expect(controller.activeFavoriteID == nil)
        #expect(controller.activeFavoriteWorkspaceState == nil)
        #expect(!controller.isActive)
    }

    @Test @MainActor func activateSetsIDAndWorkspaceState() {
        let controller = FavoriteWorkspaceController()
        let id = UUID()
        let state = ReaderFavoriteWorkspaceState.from(
            settings: .default, pinnedGroupIDs: ["pinned"], collapsedGroupIDs: [], sidebarWidth: 300
        )
        controller.activate(id: id, workspaceState: state)
        #expect(controller.activeFavoriteID == id)
        #expect(controller.activeFavoriteWorkspaceState == state)
        #expect(controller.isActive)
    }

    @Test @MainActor func deactivateClearsBothProperties() {
        let controller = FavoriteWorkspaceController()
        controller.activate(
            id: UUID(),
            workspaceState: .from(settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [], sidebarWidth: 250)
        )
        controller.deactivate()
        #expect(controller.activeFavoriteID == nil)
        #expect(controller.activeFavoriteWorkspaceState == nil)
        #expect(!controller.isActive)
    }

    @Test @MainActor func updateSidebarWidthWhenActive() {
        let controller = FavoriteWorkspaceController()
        controller.activate(
            id: UUID(),
            workspaceState: .from(settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [], sidebarWidth: 250)
        )
        controller.updateSidebarWidth(320)
        #expect(controller.activeFavoriteWorkspaceState?.sidebarWidth == 320)
    }

    @Test @MainActor func updateSidebarWidthWhenInactiveIsNoOp() {
        let controller = FavoriteWorkspaceController()
        controller.updateSidebarWidth(320)
        #expect(controller.activeFavoriteWorkspaceState == nil)
    }

    @Test @MainActor func updateLockedAppearanceMutatesState() {
        let controller = FavoriteWorkspaceController()
        controller.activate(
            id: UUID(),
            workspaceState: .from(settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [], sidebarWidth: 250)
        )
        let appearance = LockedAppearance(readerTheme: .blackOnWhite, baseFontSize: 16, syntaxTheme: .monokai)
        controller.updateLockedAppearance(appearance)
        #expect(controller.activeFavoriteWorkspaceState?.lockedAppearance == appearance)
    }

    @Test @MainActor func updateSidebarPositionMutatesState() {
        let controller = FavoriteWorkspaceController()
        controller.activate(
            id: UUID(),
            workspaceState: .from(settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [], sidebarWidth: 250)
        )
        controller.updateSidebarPosition(.sidebarRight)
        #expect(controller.activeFavoriteWorkspaceState?.sidebarPosition == .sidebarRight)
    }

    @Test @MainActor func updateGroupStateMutatesRelevantFields() {
        let controller = FavoriteWorkspaceController()
        controller.activate(
            id: UUID(),
            workspaceState: .from(settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [], sidebarWidth: 250)
        )
        controller.updateGroupState(
            pinnedGroupIDs: ["a", "b"], collapsedGroupIDs: ["c"],
            groupSortMode: .nameAscending, fileSortMode: .nameDescending,
            manualGroupOrder: ["/path/one"]
        )
        let state = controller.activeFavoriteWorkspaceState
        #expect(state?.pinnedGroupIDs == ["a", "b"])
        #expect(state?.collapsedGroupIDs == ["c"])
        #expect(state?.groupSortMode == .nameAscending)
        #expect(state?.fileSortMode == .nameDescending)
        #expect(state?.manualGroupOrder == ["/path/one"])
    }

    @Test @MainActor func matchingFavoriteFindsMatchByFolderPathAndOptions() {
        let controller = FavoriteWorkspaceController()
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder")
        let options = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly, scope: .selectedFolderOnly, excludedSubdirectoryPaths: []
        )
        let favorite = ReaderFavoriteWatchedFolder(
            name: "Test", folderPath: folderURL.path, options: options, bookmarkData: nil, createdAt: .now
        )
        let result = controller.matchingFavorite(folderURL: folderURL, options: options, in: [favorite])
        #expect(result?.id == favorite.id)
    }

    @Test @MainActor func matchingFavoriteReturnsNilWhenNoMatch() {
        let controller = FavoriteWorkspaceController()
        let result = controller.matchingFavorite(
            folderURL: URL(fileURLWithPath: "/tmp/no-match"), options: .default, in: []
        )
        #expect(result == nil)
    }

    @Test @MainActor func persistFinalStateWritesToSettingsStore() {
        let controller = FavoriteWorkspaceController()
        let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        store.addFavoriteWatchedFolder(name: "Persist", folderURL: URL(fileURLWithPath: "/tmp/persist"), options: .default)
        let favoriteID = store.currentSettings.favoriteWatchedFolders.first!.id
        var workspaceState = ReaderFavoriteWorkspaceState.from(
            settings: .default, pinnedGroupIDs: ["pinned1"], collapsedGroupIDs: [], sidebarWidth: 350
        )
        workspaceState.fileSortMode = .nameAscending
        controller.activate(id: favoriteID, workspaceState: workspaceState)
        controller.persistFinalState(to: store)
        let persisted = store.currentSettings.favoriteWatchedFolders.first!
        #expect(persisted.workspaceState.pinnedGroupIDs == ["pinned1"])
        #expect(persisted.workspaceState.sidebarWidth == 350)
        #expect(persisted.workspaceState.fileSortMode == .nameAscending)
    }

    @Test @MainActor func persistFinalStateIsNoOpWhenInactive() {
        let controller = FavoriteWorkspaceController()
        let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        store.addFavoriteWatchedFolder(name: "NoOp", folderURL: URL(fileURLWithPath: "/tmp/no-persist"), options: .default)
        controller.persistFinalState(to: store)
        let persisted = store.currentSettings.favoriteWatchedFolders.first!
        #expect(persisted.workspaceState == ReaderFavoriteWorkspaceState.from(
            settings: .default, pinnedGroupIDs: [], collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        ))
    }
}
