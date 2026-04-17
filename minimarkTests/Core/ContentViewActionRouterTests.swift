import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ContentViewActionRouterTests {

    @MainActor
    private final class TestRouterEnvironment {
        let harness: SidebarControllerTestHarness
        let appearanceController: WindowAppearanceController
        let documentOpen: WindowDocumentOpenCoordinator
        let appearanceLock: AppearanceLockCoordinator
        let folderWatchOpen: WindowFolderWatchOpenController
        var confirmFolderWatchCalls: [FolderWatchOptions] = []
        var stopFolderWatchCalls = 0
        var startFavoriteWatchCalls: [FavoriteWatchedFolder] = []
        var setEditingSubfoldersCalls: [Bool] = []
        var setEditingFavoritesCalls: [Bool] = []
        var applyTitleCalls = 0
        let router: ContentViewActionRouter

        init() throws {
            let harness = try SidebarControllerTestHarness()
            self.harness = harness
            self.appearanceController = WindowAppearanceController(settingsStore: harness.settingsStore)
            self.folderWatchOpen = WindowFolderWatchOpenController(
                fileOpenCoordinator: harness.controller.fileOpenCoordinator,
                isHostWindowAttached: { false },
                onAfterFlush: {}
            )
            self.documentOpen = WindowDocumentOpenCoordinator(
                fileOpenCoordinator: harness.controller.fileOpenCoordinator,
                folderWatchOpen: folderWatchOpen,
                sidebarDocumentController: harness.controller,
                settingsStore: harness.settingsStore,
                folderWatchSessionProvider: { nil },
                applyTitlePresentation: {},
                refreshWindowPresentation: {},
                prepareRecentFolderWatch: { _, _ in }
            )
            self.appearanceLock = AppearanceLockCoordinator(
                appearanceControllerProvider: { [appearanceController] in appearanceController },
                sidebarDocumentController: harness.controller,
                favoriteWorkspaceControllerProvider: { nil }
            )

            // Box mutable state in a class so init-time closures can write to it.
            let state = MutableState()
            self.router = ContentViewActionRouter(
                documentOpen: documentOpen,
                appearanceLock: appearanceLock,
                sidebarDocumentController: harness.controller,
                settingsStore: harness.settingsStore,
                folderWatchFlowControllerProvider: { nil },
                favoriteWorkspaceControllerProvider: { nil },
                recentHistoryCoordinatorProvider: { nil },
                fileOpenCoordinator: harness.controller.fileOpenCoordinator,
                sidebarWidthProvider: { 320 },
                applyTitlePresentation: { state.applyTitleCalls += 1 },
                confirmFolderWatch: { state.confirmFolderWatchCalls.append($0) },
                stopFolderWatch: { state.stopFolderWatchCalls += 1 },
                startFavoriteWatch: { state.startFavoriteWatchCalls.append($0) },
                setEditingSubfolders: { state.setEditingSubfoldersCalls.append($0) },
                setEditingFavorites: { state.setEditingFavoritesCalls.append($0) }
            )
            self.state = state
        }

        let state: MutableState

        @MainActor
        final class MutableState {
            var confirmFolderWatchCalls: [FolderWatchOptions] = []
            var stopFolderWatchCalls = 0
            var startFavoriteWatchCalls: [FavoriteWatchedFolder] = []
            var setEditingSubfoldersCalls: [Bool] = []
            var setEditingFavoritesCalls: [Bool] = []
            var applyTitleCalls = 0
        }
    }

    @Test @MainActor
    func contentViewActionRoutesEditSubfoldersToFlagSetter() throws {
        let env = try TestRouterEnvironment()
        defer { env.harness.cleanup() }

        env.router.handle(ContentViewAction.editSubfolders)

        #expect(env.state.setEditingSubfoldersCalls == [true])
    }

    @Test @MainActor
    func contentViewActionRoutesStopFolderWatchToCallback() throws {
        let env = try TestRouterEnvironment()
        defer { env.harness.cleanup() }

        env.router.handle(ContentViewAction.stopFolderWatch)

        #expect(env.state.stopFolderWatchCalls == 1)
    }

    @Test @MainActor
    func folderWatchToolbarEditFavoritesSetsFlag() throws {
        let env = try TestRouterEnvironment()
        defer { env.harness.cleanup() }

        env.router.handle(FolderWatchToolbarAction.editFavoriteWatchedFolders)

        #expect(env.state.setEditingFavoritesCalls == [true])
    }

    @Test @MainActor
    func editFavoritesDismissUnsetsFlag() throws {
        let env = try TestRouterEnvironment()
        defer { env.harness.cleanup() }

        env.router.handle(EditFavoritesAction.dismiss)

        #expect(env.state.setEditingFavoritesCalls == [false])
    }

    @Test @MainActor
    func contentViewActionToggleAppearanceLockTogglesController() throws {
        let env = try TestRouterEnvironment()
        defer { env.harness.cleanup() }

        #expect(env.appearanceController.isLocked == false)
        env.router.handle(ContentViewAction.toggleAppearanceLock)
        #expect(env.appearanceController.isLocked == true)
    }
}
