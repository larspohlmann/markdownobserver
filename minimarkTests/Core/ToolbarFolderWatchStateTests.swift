import Testing
import Foundation
@testable import minimark

struct ToolbarFolderWatchStateTests {
    @Test
    func equatableReflectsAllFields() {
        let a = ToolbarFolderWatchState(
            activeFolderWatch: nil,
            isInitialScanInProgress: false,
            didInitialScanFail: false,
            favoriteWatchedFolders: [],
            recentWatchedFolders: []
        )
        let b = ToolbarFolderWatchState(
            activeFolderWatch: nil,
            isInitialScanInProgress: true,
            didInitialScanFail: false,
            favoriteWatchedFolders: [],
            recentWatchedFolders: []
        )
        #expect(a != b)
    }

    @Test
    func idleStateProducesExpectedShape() {
        let state = ToolbarFolderWatchState(
            activeFolderWatch: nil,
            isInitialScanInProgress: false,
            didInitialScanFail: false,
            favoriteWatchedFolders: [],
            recentWatchedFolders: []
        )

        #expect(state.activeFolderWatch == nil)
        #expect(state.isInitialScanInProgress == false)
        #expect(state.didInitialScanFail == false)
        #expect(state.favoriteWatchedFolders.isEmpty)
        #expect(state.recentWatchedFolders.isEmpty)
    }
}
