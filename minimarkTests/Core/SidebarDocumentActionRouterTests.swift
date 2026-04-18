import CoreGraphics
import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct SidebarDocumentActionRouterTests {

    @MainActor
    private func makeRouter(
        favoriteWorkspaceController: FavoriteWorkspaceController? = nil,
        sidebarWidth: CGFloat = SidebarWorkspaceMetrics.sidebarIdealWidth,
        onAfterRefresh: @escaping () -> Void = {}
    ) throws -> (SidebarDocumentActionRouter, SidebarControllerTestHarness) {
        let harness = try SidebarControllerTestHarness()
        let router = SidebarDocumentActionRouter(
            sidebarDocumentController: harness.controller,
            settingsStore: harness.settingsStore,
            favoriteWorkspaceControllerProvider: { favoriteWorkspaceController },
            sidebarWidthProvider: { sidebarWidth },
            refreshWindowPresentation: onAfterRefresh
        )
        return (router, harness)
    }

    @Test @MainActor
    func mutatingActionsTriggerRefresh() throws {
        var refreshCalls = 0
        let (router, harness) = try makeRouter(onAfterRefresh: { refreshCalls += 1 })
        defer { harness.cleanup() }

        router.closeAllDocuments()
        #expect(refreshCalls == 1)

        router.closeOtherDocuments(keeping: [])
        #expect(refreshCalls == 2)

        router.stopWatchingFolders([])
        #expect(refreshCalls == 3)
    }

    @Test @MainActor
    func nonMutatingActionsDoNotTriggerRefresh() throws {
        var refreshCalls = 0
        let (router, harness) = try makeRouter(onAfterRefresh: { refreshCalls += 1 })
        defer { harness.cleanup() }

        router.openDocumentsInDefaultApp([])
        router.revealDocumentsInFinder([])

        #expect(refreshCalls == 0)
    }

    @Test @MainActor
    func toggleSidebarPlacementWithoutFavoriteUpdatesSettings() throws {
        let (router, harness) = try makeRouter()
        defer { harness.cleanup() }

        let initialMode = harness.settingsStore.currentSettings.multiFileDisplayMode
        router.toggleSidebarPlacement(currentMultiFileDisplayMode: initialMode)

        #expect(harness.settingsStore.currentSettings.multiFileDisplayMode == initialMode.toggledSidebarPlacementMode)
    }
}
