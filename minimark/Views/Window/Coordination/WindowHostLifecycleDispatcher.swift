import AppKit

/// Bridges the SwiftUI `.background(WindowAccessor)` callback into the window
/// shell. When the host `NSWindow` attaches/changes, refreshes shell state,
/// applies the UI-test configuration, and flushes pending folder-watch opens.
@MainActor
final class WindowHostLifecycleDispatcher {
    private let shell: WindowShellController
    private let folderWatchOpen: WindowFolderWatchOpenController
    private let uiTestLaunchCoordinatorProvider: () -> UITestLaunchCoordinator?
    private let refreshWindowShellState: () -> Void

    init(
        shell: WindowShellController,
        folderWatchOpen: WindowFolderWatchOpenController,
        uiTestLaunchCoordinatorProvider: @escaping () -> UITestLaunchCoordinator?,
        refreshWindowShellState: @escaping () -> Void
    ) {
        self.shell = shell
        self.folderWatchOpen = folderWatchOpen
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
}
