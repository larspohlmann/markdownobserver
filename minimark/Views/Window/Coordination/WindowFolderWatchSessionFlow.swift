import AppKit
import Foundation

/// Composite flows that start, stop, confirm, or otherwise mutate the window's
/// folder-watch session — and the sidebar width along with it, since activating
/// or deactivating a watch changes the sidebar's visible state.
///
/// Bundled here instead of on the window coordinator because every one of
/// these methods is the same shape: call `FolderWatchFlowController`, reset
/// the sidebar width on deactivation, refresh window presentation. Keeping
/// them together makes the shared pattern visible and isolates the mutation
/// path for testing.
@MainActor
final class WindowFolderWatchSessionFlow {
    private let folderWatchFlowControllerProvider: () -> FolderWatchFlowController?
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let sidebarMetrics: WindowSidebarMetricsController
    private let hostWindowProvider: () -> NSWindow?
    private let refreshWindowPresentation: () -> Void

    init(
        folderWatchFlowControllerProvider: @escaping () -> FolderWatchFlowController?,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        sidebarMetrics: WindowSidebarMetricsController,
        hostWindowProvider: @escaping () -> NSWindow?,
        refreshWindowPresentation: @escaping () -> Void
    ) {
        self.folderWatchFlowControllerProvider = folderWatchFlowControllerProvider
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.sidebarMetrics = sidebarMetrics
        self.hostWindowProvider = hostWindowProvider
        self.refreshWindowPresentation = refreshWindowPresentation
    }

    func startFavoriteWatch(_ entry: FavoriteWatchedFolder) {
        guard let favoriteWorkspaceController = favoriteWorkspaceControllerProvider() else { return }
        sidebarMetrics.width = favoriteWorkspaceController.startFavoriteWatch(entry)
        refreshWindowPresentation()
    }

    func startWatchingFolder(
        folderURL: URL,
        options: FolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) {
        let deactivated = folderWatchFlowControllerProvider()?.startWatchingFolder(
            folderURL: folderURL,
            options: options,
            performInitialAutoOpen: performInitialAutoOpen
        ) ?? false
        if deactivated {
            sidebarMetrics.resetToIdealWidth()
        }
        refreshWindowPresentation()
    }

    @discardableResult
    func updateExclusions(_ newExcludedPaths: [String]) -> Bool {
        let result = folderWatchFlowControllerProvider()?.updateFolderWatchExclusions(newExcludedPaths) ?? false
        refreshWindowPresentation()
        return result
    }

    func confirm(_ options: FolderWatchOptions) {
        let deactivated = folderWatchFlowControllerProvider()?.confirmFolderWatch(options) ?? false
        if deactivated {
            sidebarMetrics.resetToIdealWidth()
        }
        refreshWindowPresentation()
    }

    func stop() {
        folderWatchFlowControllerProvider()?.stopFolderWatchSession()
        sidebarMetrics.resetToIdealWidth()
        refreshWindowPresentation()
    }

    func handleAutoOpenWarningChange(_ warning: FolderWatchAutoOpenWarning?) {
        folderWatchFlowControllerProvider()?.handleAutoOpenWarningChangeForWindow(warning, hostWindow: hostWindowProvider())
    }

    func refreshAutoOpenWarningPresentation() {
        folderWatchFlowControllerProvider()?.refreshAutoOpenWarningPresentationForWindow(hostWindow: hostWindowProvider())
    }

    func openSelectedAutoOpenFiles() {
        folderWatchFlowControllerProvider()?.openSelectedAutoOpenFilesAndRefresh()
        refreshWindowPresentation()
    }
}
