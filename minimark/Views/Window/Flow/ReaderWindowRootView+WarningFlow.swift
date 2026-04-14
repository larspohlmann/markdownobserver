import AppKit
import Foundation

extension ReaderWindowRootView {
    func cancelFolderWatch() {
        isFolderWatchOptionsPresented = false
        pendingFolderWatchRequest = nil
    }

    func confirmFolderWatch(_ options: ReaderFolderWatchOptions) {
        guard let folderURL = pendingFolderWatchRequest?.folderURL else {
            return
        }

        startWatchingFolder(folderURL: folderURL, options: options)
        cancelFolderWatch()
    }

    func stopFolderWatch() {
        dismissFolderWatchAutoOpenWarning()
        persistFinalWorkspaceStateIfNeeded()
        activeFavoriteID = nil
        activeFavoriteWorkspaceState = nil
        groupStateController.pinnedGroupIDs = []
        groupStateController.collapsedGroupIDs = []
        sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        sidebarDocumentController.folderWatchCoordinator.stopFolderWatch()
        refreshWindowPresentation()
        cancelFolderWatch()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchWarningCoordinator.handleWarningChange(warning) {
            isFolderWatchWarningPresentationAllowed()
        }
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        let warning = sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning
        handleFolderWatchAutoOpenWarningChange(warning)
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchWarningCoordinator.dismiss {
            sidebarDocumentController.folderWatchCoordinator.dismissFolderWatchAutoOpenWarnings()
        }
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        let selectedFileURLs = folderWatchWarningCoordinator.selectedFileURLs()
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
        let targetWindow = hostWindow ?? NSApp.keyWindow
        return !isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }
}
