import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderFavoriteWorkspaceStateTests {
    @Test func codableRoundTripPreservesAllFields() throws {
        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 300,
            pinnedGroupIDs: ["groupA", "groupB"],
            collapsedGroupIDs: ["groupC"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.fileSortMode == .nameAscending)
        #expect(decoded.groupSortMode == .lastChangedNewestFirst)
        #expect(decoded.sidebarPosition == .sidebarRight)
        #expect(decoded.sidebarWidth == 300)
        #expect(decoded.pinnedGroupIDs == ["groupA", "groupB"])
        #expect(decoded.collapsedGroupIDs == ["groupC"])
        #expect(decoded.manualGroupOrder == nil)
    }

    @Test func codableRoundTripPreservesManualGroupOrder() throws {
        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .manualOrder,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 300,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            manualGroupOrder: ["/path/gamma", "/path/alpha"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: data)

        #expect(decoded.manualGroupOrder == ["/path/gamma", "/path/alpha"])
        #expect(decoded.groupSortMode == .manualOrder)
    }

    @Test func defaultFactoryUsesGlobalSettingsAndEmptySets() {
        let settings = ReaderSettings.default

        let state = ReaderFavoriteWorkspaceState.from(
            settings: settings,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )

        #expect(state.fileSortMode == settings.sidebarSortMode)
        #expect(state.groupSortMode == settings.sidebarGroupSortMode)
        #expect(state.sidebarPosition == settings.multiFileDisplayMode)
        #expect(state.sidebarWidth == ReaderFavoriteWorkspaceState.defaultSidebarWidth)
        #expect(state.pinnedGroupIDs.isEmpty)
        #expect(state.collapsedGroupIDs.isEmpty)
    }

    @Test func snapshotCapturesCurrentValues() {
        let state = ReaderFavoriteWorkspaceState.from(
            settings: ReaderSettings.default,
            pinnedGroupIDs: ["pinned1"],
            collapsedGroupIDs: ["collapsed1", "collapsed2"],
            sidebarWidth: 350
        )

        #expect(state.pinnedGroupIDs == ["pinned1"])
        #expect(state.collapsedGroupIDs == ["collapsed1", "collapsed2"])
        #expect(state.sidebarWidth == 350)
    }

    @Test func favoriteWithWorkspaceStateRoundTripsViaReaderSettings() throws {
        let workspaceState = ReaderFavoriteWorkspaceState(
            fileSortMode: .lastChangedOldestFirst,
            groupSortMode: .nameDescending,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 275,
            pinnedGroupIDs: ["dir1", "dir2"],
            collapsedGroupIDs: ["dir3"]
        )

        let favorite = ReaderFavoriteWatchedFolder(
            name: "Integration Test",
            folderPath: "/tmp/integration",
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: []
            ),
            bookmarkData: nil,
            openDocumentRelativePaths: ["a.md", "b.md"],
            allKnownRelativePaths: ["a.md", "b.md", "c.md"],
            workspaceState: workspaceState,
            createdAt: .now
        )

        var settings = ReaderSettings.default
        settings.favoriteWatchedFolders = [favorite]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)

        let restoredFavorite = decoded.favoriteWatchedFolders.first!
        #expect(restoredFavorite.workspaceState == workspaceState)
        #expect(restoredFavorite.workspaceState.fileSortMode == .lastChangedOldestFirst)
        #expect(restoredFavorite.workspaceState.pinnedGroupIDs == ["dir1", "dir2"])
        #expect(restoredFavorite.workspaceState.sidebarWidth == 275)
    }

    @Test @MainActor func workspaceStateUpdatePersistsAndRoundTrips() {
        let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        let folderURL = URL(fileURLWithPath: "/tmp/roundtrip")
        let options = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "RoundTrip",
            folderURL: folderURL,
            options: options,
            workspaceState: .from(
                settings: .default,
                pinnedGroupIDs: [],
                collapsedGroupIDs: [],
                sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
            )
        )

        let favoriteID = store.currentSettings.favoriteWatchedFolders.first!.id

        // Initial workspace state should have defaults
        let initial = store.currentSettings.favoriteWatchedFolders.first!.workspaceState
        #expect(initial.pinnedGroupIDs.isEmpty)
        #expect(initial.collapsedGroupIDs.isEmpty)

        // Update workspace state
        var updated = initial
        updated.fileSortMode = .nameAscending
        updated.pinnedGroupIDs = ["group1"]
        updated.sidebarWidth = 300

        store.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: updated)

        // Verify persisted
        let persisted = store.currentSettings.favoriteWatchedFolders.first!
        #expect(persisted.workspaceState.fileSortMode == .nameAscending)
        #expect(persisted.workspaceState.pinnedGroupIDs == ["group1"])
        #expect(persisted.workspaceState.sidebarWidth == 300)
        #expect(persisted.name == "RoundTrip") // other fields unchanged
    }

    @Test func legacyMigrationUsesDecodedGlobalSettings() throws {
        // Simulate settings with customized globals and a legacy favorite (no workspaceState key)
        var settings = ReaderSettings.default
        settings.sidebarSortMode = .nameAscending
        settings.sidebarGroupSortMode = .nameDescending
        settings.multiFileDisplayMode = .sidebarRight

        let favorite = ReaderFavoriteWatchedFolder(
            name: "Legacy",
            folderPath: "/tmp/legacy",
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly,
                excludedSubdirectoryPaths: []
            ),
            bookmarkData: nil,
            createdAt: .now
        )
        settings.favoriteWatchedFolders = [favorite]

        // Encode, then decode — simulates upgrade path where favorite has default workspace state
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)

        let migrated = decoded.favoriteWatchedFolders.first!
        #expect(migrated.workspaceState.fileSortMode == .nameAscending)
        #expect(migrated.workspaceState.groupSortMode == .nameDescending)
        #expect(migrated.workspaceState.sidebarPosition == .sidebarRight)
    }
}
