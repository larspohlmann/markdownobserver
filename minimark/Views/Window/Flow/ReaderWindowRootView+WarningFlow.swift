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
        folderWatchFlowController.warningCoordinator.handleWarningChange(warning) {
            isFolderWatchWarningPresentationAllowed()
        }
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        let warning = sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning
        handleFolderWatchAutoOpenWarningChange(warning)
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchFlowController.warningCoordinator.dismiss {
            sidebarDocumentController.folderWatchCoordinator.dismissFolderWatchAutoOpenWarnings()
        }
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        let selectedFileURLs = folderWatchFlowController.warningCoordinator.selectedFileURLs()
        guard !selectedFileURLs.isEmpty else {
            dismissFolderWatchAutoOpenWarning()
            return
        }

        dismissFolderWatchAutoOpenWarning()
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: selectedFileURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))
        refreshWindowPresentation()
    }

    func isFolderWatchWarningPresentationAllowed() -> Bool {
        let targetWindow = windowCoordinator.hostWindow ?? NSApp.keyWindow
        return !folderWatchFlowController.isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }
}
