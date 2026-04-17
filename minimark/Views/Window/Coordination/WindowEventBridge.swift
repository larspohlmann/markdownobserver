import AppKit
import Foundation

/// Translates SwiftUI window events (.background WindowAccessor, .onAppear,
/// .onDisappear, .onChange of various properties) into mutations on the
/// extracted controllers. Holds no business logic of its own — every method
/// is a thin reducer dispatching to one or more collaborators.
///
/// Bundled here because every method is the same shape: a SwiftUI hook fires,
/// the bridge decides which collaborators need to know. Splitting one method
/// per file would just disperse that uniform pattern.
@MainActor
final class WindowEventBridge {
    let openDocumentPathTracker = OpenDocumentPathTracker()

    private let shell: WindowShellController
    private let folderWatchOpen: WindowFolderWatchOpenController
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let settingsStore: ReaderSettingsStore
    private let groupStateControllerProvider: () -> SidebarGroupStateController?
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let appearanceControllerProvider: () -> WindowAppearanceController?
    private let uiTestLaunchCoordinatorProvider: () -> UITestLaunchCoordinator?
    private let refreshWindowShellState: () -> Void

    init(
        shell: WindowShellController,
        folderWatchOpen: WindowFolderWatchOpenController,
        sidebarDocumentController: ReaderSidebarDocumentController,
        settingsStore: ReaderSettingsStore,
        groupStateControllerProvider: @escaping () -> SidebarGroupStateController?,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        appearanceControllerProvider: @escaping () -> WindowAppearanceController?,
        uiTestLaunchCoordinatorProvider: @escaping () -> UITestLaunchCoordinator?,
        refreshWindowShellState: @escaping () -> Void
    ) {
        self.shell = shell
        self.folderWatchOpen = folderWatchOpen
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.groupStateControllerProvider = groupStateControllerProvider
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.appearanceControllerProvider = appearanceControllerProvider
        self.uiTestLaunchCoordinatorProvider = uiTestLaunchCoordinatorProvider
        self.refreshWindowShellState = refreshWindowShellState
    }

    func handleWindowAccessorUpdate(_ window: NSWindow?) {
        guard shell.updateHostWindow(window) else { return }
        handleHostWindowChange()
    }

    private func handleHostWindowChange() {
        refreshWindowShellState()
        uiTestLaunchCoordinatorProvider()?.applyConfigurationIfNeeded()
        if shell.hostWindow != nil, folderWatchOpen.hasPendingEvents {
            folderWatchOpen.flush()
        }
    }

    func handleWindowAppear() {
        let groupState = groupStateControllerProvider()
        groupState?.configureSortModes(
            sortMode: settingsStore.currentSettings.sidebarGroupSortMode,
            fileSortMode: settingsStore.currentSettings.sidebarSortMode
        )
        groupState?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        groupState?.observeRowStates(from: sidebarDocumentController)
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
        shell.configureDockTile()
    }

    func handleWindowDisappear() {
        shell.clearDockTile()
    }

    func handleDocumentListChange() {
        groupStateControllerProvider()?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
    }

    func handleFavoriteWorkspaceStateChange(_ newState: ReaderFavoriteWorkspaceState?) {
        guard let favoriteID = favoriteWorkspaceControllerProvider()?.activeFavoriteID,
              var state = newState else { return }
        state.lockedAppearance = appearanceControllerProvider()?.lockedAppearance
        settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
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
