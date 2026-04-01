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
}
