import AppKit
import Foundation

extension ReaderWindowRootView {
    func cancelFolderWatch() {
        folderWatchFlowController.cancelPendingWatch()
    }

    func confirmFolderWatch(_ options: ReaderFolderWatchOptions) {
        guard let folderURL = folderWatchFlowController.pendingFolderWatchRequest?.folderURL else {
            return
        }

        startWatchingFolder(folderURL: folderURL, options: options)
        cancelFolderWatch()
    }

    func stopFolderWatch() {
        dismissFolderWatchAutoOpenWarning()
        favoriteWorkspaceController.persistFinalState(to: settingsStore)
        favoriteWorkspaceController.deactivate()
        groupStateController.pinnedGroupIDs = []
        groupStateController.collapsedGroupIDs = []
        windowCoordinator.sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        sidebarDocumentController.folderWatchCoordinator.stopFolderWatch()
        refreshWindowPresentation()
        cancelFolderWatch()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchFlowController.handleAutoOpenWarningChange(warning) { [self] in
            isFolderWatchWarningPresentationAllowed()
        }
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        folderWatchFlowController.refreshAutoOpenWarningPresentation { [self] in
            isFolderWatchWarningPresentationAllowed()
        }
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchFlowController.dismissAutoOpenWarning()
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        folderWatchFlowController.openSelectedAutoOpenFiles(using: fileOpenCoordinator)
        refreshWindowPresentation()
    }

    func isFolderWatchWarningPresentationAllowed() -> Bool {
        folderWatchFlowController.isWarningPresentationAllowed(hostWindow: windowCoordinator.hostWindow)
    }
}
