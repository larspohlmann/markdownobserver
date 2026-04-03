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
        sidebarPinnedGroupIDs = []
        sidebarCollapsedGroupIDs = []
        sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        sidebarDocumentController.stopFolderWatch()
        refreshWindowPresentation()
        cancelFolderWatch()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchWarningCoordinator.handleWarningChange(warning) {
            isFolderWatchWarningPresentationAllowed()
        }
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        let warning = sidebarDocumentController.selectedFolderWatchAutoOpenWarning
        handleFolderWatchAutoOpenWarningChange(warning)
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchWarningCoordinator.dismiss {
            sidebarDocumentController.dismissFolderWatchAutoOpenWarnings()
        }
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        let selectedFileURLs = folderWatchWarningCoordinator.selectedFileURLs()
        guard !selectedFileURLs.isEmpty else {
            dismissFolderWatchAutoOpenWarning()
            return
        }

        dismissFolderWatchAutoOpenWarning()
        openSidebarDocumentsBurst(at: selectedFileURLs, preferEmptySelection: false)
    }

    func isFolderWatchWarningPresentationAllowed() -> Bool {
        let targetWindow = hostWindow ?? NSApp.keyWindow
        return !isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }
}
