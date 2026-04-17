import Foundation

/// Routes sidebar document actions (close, open externally, reveal, stop
/// watching, toggle placement) to the underlying sidebar document controller
/// and refreshes the window presentation afterwards.
///
/// Each mutating action runs through `performSidebarMutation(_:)` so that the
/// title and shared folder-watch state stay consistent with the sidebar's
/// current document set. Pure pass-throughs (open in app, reveal in Finder)
/// skip the refresh because they don't change the sidebar's document list.
@MainActor
final class SidebarDocumentActionRouter {
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let settingsStore: ReaderSettingsStore
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let sidebarWidthProvider: () -> CGFloat
    private let refreshWindowPresentation: () -> Void

    init(
        sidebarDocumentController: ReaderSidebarDocumentController,
        settingsStore: ReaderSettingsStore,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        sidebarWidthProvider: @escaping () -> CGFloat,
        refreshWindowPresentation: @escaping () -> Void
    ) {
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.sidebarWidthProvider = sidebarWidthProvider
        self.refreshWindowPresentation = refreshWindowPresentation
    }

    func closeDocument(_ documentID: UUID) {
        performSidebarMutation { sidebarDocumentController.closeDocument(documentID) }
    }

    func closeOtherDocuments(keeping documentIDs: Set<UUID>) {
        performSidebarMutation { sidebarDocumentController.closeOtherDocuments(keeping: documentIDs) }
    }

    func closeSelectedDocuments(_ documentIDs: Set<UUID>) {
        performSidebarMutation { sidebarDocumentController.closeDocuments(documentIDs) }
    }

    func closeAllDocuments() {
        performSidebarMutation { sidebarDocumentController.closeAllDocuments() }
    }

    func openDocumentsInDefaultApp(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(nil, documentIDs: documentIDs)
    }

    func openDocumentsInApplication(_ application: ExternalApplication, _ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(application, documentIDs: documentIDs)
    }

    func revealDocumentsInFinder(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.revealDocumentsInFinder(documentIDs)
    }

    func stopWatchingFolders(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.folderWatchCoordinator.stopWatchingFolders(documentIDs)
        }
    }

    func toggleSidebarPlacement(currentMultiFileDisplayMode: MultiFileDisplayMode) {
        if let favoriteController = favoriteWorkspaceControllerProvider(),
           let current = favoriteController.activeFavoriteWorkspaceState?.sidebarPosition {
            favoriteController.updateSidebarPosition(current.toggledSidebarPlacementMode)
            favoriteController.updateSidebarWidth(sidebarWidthProvider())
        } else {
            settingsStore.updateMultiFileDisplayMode(currentMultiFileDisplayMode.toggledSidebarPlacementMode)
        }
    }

    private func performSidebarMutation(_ mutation: () -> Void) {
        mutation()
        refreshWindowPresentation()
    }
}
