import XCTest
@testable import minimark

final class ReaderFavoriteWorkspaceStateLockTests: XCTestCase {
    func testWorkspaceStateDefaultsToNilLockedAppearance() {
        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .openOrder,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarLeft,
            sidebarWidth: 250,
            pinnedGroupIDs: [],
            collapsedGroupIDs: []
        )

        XCTAssertNil(state.lockedAppearance)
    }

    func testWorkspaceStateStoresLockedAppearance() {
        var state = ReaderFavoriteWorkspaceState(
            fileSortMode: .openOrder,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarLeft,
            sidebarWidth: 250,
            pinnedGroupIDs: [],
            collapsedGroupIDs: []
        )
        let locked = LockedAppearance(readerTheme: .newspaper, baseFontSize: 20, syntaxTheme: .github)
        state.lockedAppearance = locked

        XCTAssertEqual(state.lockedAppearance, locked)
    }

    func testWorkspaceStateWithoutLockedAppearanceDecodesFromLegacyJSON() throws {
        // Simulates existing persisted data that predates the lockedAppearance field
        let legacyJSON = """
        {
            "fileSortMode": "openOrder",
            "groupSortMode": "lastChangedNewestFirst",
            "sidebarPosition": "sidebarLeft",
            "sidebarWidth": 250,
            "pinnedGroupIDs": [],
            "collapsedGroupIDs": []
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: legacyJSON)
        XCTAssertNil(state.lockedAppearance)
    }

    func testWorkspaceStateWithLockedAppearanceRoundTrips() throws {
        var state = ReaderFavoriteWorkspaceState(
            fileSortMode: .openOrder,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarLeft,
            sidebarWidth: 250,
            pinnedGroupIDs: [],
            collapsedGroupIDs: []
        )
        state.lockedAppearance = LockedAppearance(
            readerTheme: .commodore64,
            baseFontSize: 16,
            syntaxTheme: .solarizedDark
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: data)

        XCTAssertEqual(decoded.lockedAppearance?.readerTheme, .commodore64)
        XCTAssertEqual(decoded.lockedAppearance?.baseFontSize, 16)
        XCTAssertEqual(decoded.lockedAppearance?.syntaxTheme, .solarizedDark)
    }
}
