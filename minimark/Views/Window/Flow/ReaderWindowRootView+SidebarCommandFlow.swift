import AppKit
import Foundation

extension ReaderWindowRootView {
    func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)

        if ReaderWindowRegistry.shared.focusDocumentIfAlreadyOpen(at: normalizedFileURL) {
            return
        }

        if folderWatchSession != nil {
            enqueueFolderWatchOpen(
                folderWatchChangeEvent(
                    for: normalizedFileURL,
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                ),
                folderWatchSession: folderWatchSession,
                origin: origin
            )
            return
        }

        sidebarDocumentController.openAdditionalDocument(
            at: normalizedFileURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        refreshWindowPresentation()
    }

    func startRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        prepareRecentFolderWatch(entry)
    }

    func clearRecentWatchedFolders() {
        settingsStore.clearRecentWatchedFolders()
    }

    func clearRecentManuallyOpenedFiles() {
        settingsStore.clearRecentManuallyOpenedFiles()
    }

    func notificationTargetsCurrentWindow(_ notification: Notification) -> Bool {
        guard let hostWindow else {
            return false
        }

        guard let requestedWindowNumber = notification.userInfo?[ReaderCommandNotification.targetWindowNumberKey] as? Int else {
            return false
        }

        return hostWindow.windowNumber == requestedWindowNumber
    }

    func startWatchingFolder(folderURL: URL, options: ReaderFolderWatchOptions) {
        do {
            try sidebarDocumentController.startWatchingFolder(folderURL: folderURL, options: options)
        } catch {
            sidebarDocumentController.selectedReaderStore.presentError(error)
        }

        refreshWindowPresentation()
    }

    func performSidebarMutation(_ mutation: () -> Void) {
        mutation()
        refreshWindowPresentation()
    }

    func closeSidebarDocument(_ documentID: UUID) {
        performSidebarMutation {
            sidebarDocumentController.closeDocument(documentID)
        }
    }

    func openSidebarDocumentsInDefaultApp(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(nil, documentIDs: documentIDs)
    }

    func openSidebarDocumentsInApplication(_ application: ReaderExternalApplication, _ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(application, documentIDs: documentIDs)
    }

    func revealSidebarDocumentsInFinder(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.revealDocumentsInFinder(documentIDs)
    }

    func stopWatchingSidebarFolders(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.stopWatchingFolders(documentIDs)
        }
    }

    func closeOtherSidebarDocuments(keeping documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeOtherDocuments(keeping: documentIDs)
        }
    }

    func closeSelectedSidebarDocuments(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeDocuments(documentIDs)
        }
    }

    func closeAllSidebarDocuments() {
        performSidebarMutation {
            sidebarDocumentController.closeAllDocuments()
        }
    }

    func toggleSidebarPlacement() {
        settingsStore.updateMultiFileDisplayMode(multiFileDisplayMode.toggledSidebarPlacementMode)
    }
}
