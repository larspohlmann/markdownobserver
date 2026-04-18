import Foundation

/// Routes folder-watch lifecycle actions: request/confirm/cancel/stop plus
/// the edit-subfolders flag.
@MainActor
final class FolderWatchActionRouter {
    private let folderWatchFlowControllerProvider: () -> FolderWatchFlowController?
    private let callbacks: FolderWatchRouterCallbacks

    init(
        folderWatchFlowControllerProvider: @escaping () -> FolderWatchFlowController?,
        callbacks: FolderWatchRouterCallbacks
    ) {
        self.folderWatchFlowControllerProvider = folderWatchFlowControllerProvider
        self.callbacks = callbacks
    }

    func requestFolderWatch(_ url: URL) {
        folderWatchFlowControllerProvider()?.prepareOptions(for: url)
    }

    func confirmFolderWatch(_ options: FolderWatchOptions) {
        callbacks.confirmFolderWatch(options)
    }

    func cancelFolderWatch() {
        folderWatchFlowControllerProvider()?.cancelPendingWatch()
    }

    func stopFolderWatch() {
        callbacks.stopFolderWatch()
    }

    func editSubfolders() {
        callbacks.setEditingSubfolders(true)
    }
}
