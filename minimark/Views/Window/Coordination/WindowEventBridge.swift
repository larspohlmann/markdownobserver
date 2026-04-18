import AppKit
import Foundation

/// Translates SwiftUI window events (.background WindowAccessor, .onAppear,
/// .onDisappear, .onChange of various properties) into mutations on the
/// extracted controllers. A thin composite over four focused dispatchers —
/// each dispatcher owns its own slice of deps (see #373).
@MainActor
final class WindowEventBridge {
    private let hostLifecycle: WindowHostLifecycleDispatcher
    private let documentSync: WindowDocumentSyncDispatcher
    private let favoriteWorkspace: FavoriteWorkspaceEventDispatcher
    private let groupState: GroupStateEventDispatcher

    init(
        hostLifecycle: WindowHostLifecycleDispatcher,
        documentSync: WindowDocumentSyncDispatcher,
        favoriteWorkspace: FavoriteWorkspaceEventDispatcher,
        groupState: GroupStateEventDispatcher
    ) {
        self.hostLifecycle = hostLifecycle
        self.documentSync = documentSync
        self.favoriteWorkspace = favoriteWorkspace
        self.groupState = groupState
    }

    /// Read-through surface kept for `WindowRootView` consumers. The tracker
    /// itself is owned by `documentSync`, which is the only dispatcher that
    /// mutates it.
    var openDocumentPathTracker: OpenDocumentPathTracker { documentSync.openDocumentPathTracker }

    func handleWindowAccessorUpdate(_ window: NSWindow?) {
        hostLifecycle.handleWindowAccessorUpdate(window)
    }

    func handleWindowAppear() {
        documentSync.handleWindowAppear()
    }

    func handleWindowDisappear() {
        documentSync.handleWindowDisappear()
    }

    func handleDocumentListChange() {
        documentSync.handleDocumentListChange()
    }

    func handleFavoriteWorkspaceStateChange(_ newState: FavoriteWorkspaceState?) {
        favoriteWorkspace.handleFavoriteWorkspaceStateChange(newState)
    }

    func handleGroupStateChange(
        oldSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot,
        newSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot
    ) {
        groupState.handleGroupStateChange(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)
    }
}
