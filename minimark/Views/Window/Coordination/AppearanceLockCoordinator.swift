import Foundation

/// Coordinates the appearance-lock toggle and the rendering side effects that
/// follow: pushing the locked appearance onto every open document's rendering
/// controller, syncing the active favorite workspace, and re-rendering the
/// currently selected document when needed.
///
/// Distinct from `WindowAppearanceController` (which only tracks "what is the
/// effective appearance for this window?"). This coordinator owns the cross-
/// document propagation that happens when the lock state or effective
/// appearance changes.
@MainActor
final class AppearanceLockCoordinator {
    private let appearanceControllerProvider: () -> WindowAppearanceController?
    private let sidebarDocumentController: SidebarDocumentController
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?

    init(
        appearanceControllerProvider: @escaping () -> WindowAppearanceController?,
        sidebarDocumentController: SidebarDocumentController,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?
    ) {
        self.appearanceControllerProvider = appearanceControllerProvider
        self.sidebarDocumentController = sidebarDocumentController
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
    }

    func toggleLock() {
        guard let appearanceController = appearanceControllerProvider() else { return }
        if appearanceController.isLocked {
            appearanceController.unlock()
            for document in sidebarDocumentController.documents {
                document.readerStore.renderingController.clearAppearanceOverride()
            }
            if favoriteWorkspaceControllerProvider()?.activeFavoriteWorkspaceState != nil {
                favoriteWorkspaceControllerProvider()?.updateLockedAppearance(nil)
            }
        } else {
            appearanceController.lock()
            let appearance = appearanceController.effectiveAppearance
            for document in sidebarDocumentController.documents {
                document.readerStore.renderingController.setAppearanceOverride(appearance)
            }
            if favoriteWorkspaceControllerProvider()?.activeFavoriteWorkspaceState != nil {
                favoriteWorkspaceControllerProvider()?.updateLockedAppearance(appearanceController.lockedAppearance)
            }
        }
    }

    func reapplyAcrossOpenDocuments() {
        guard let appearanceController = appearanceControllerProvider() else { return }
        // Defer rendering to the next main actor hop to avoid setting @Published
        // properties on DocumentStore during a SwiftUI view update cycle.
        Task { @MainActor [sidebarDocumentController] in
            let appearance = appearanceController.effectiveAppearance
            for document in sidebarDocumentController.documents {
                let store = document.readerStore
                guard store.document.hasOpenDocument, !store.document.isDeferredDocument else { continue }

                if document.id == sidebarDocumentController.selectedDocumentID {
                    try? store.renderingController.renderWithAppearance(
                        appearance,
                        sourceMarkdown: store.document.sourceMarkdown,
                        changedRegions: store.document.changedRegions,
                        unsavedChangedRegions: store.sourceEditingController.unsavedChangedRegions,
                        fileURL: store.document.fileURL,
                        folderWatchSession: store.folderWatchDispatcher.activeFolderWatchSession
                    )
                } else {
                    store.renderingController.setAppearanceOverride(appearance)
                }
            }
        }
    }

    func renderSelectedDocumentIfNeeded() {
        guard let appearanceController = appearanceControllerProvider() else { return }
        guard let document = sidebarDocumentController.selectedDocument else { return }
        let store = document.readerStore
        guard store.renderingController.needsAppearanceRender,
              store.document.hasOpenDocument,
              !store.document.isDeferredDocument else { return }
        Task { @MainActor in
            try? store.renderingController.renderWithAppearance(
                appearanceController.effectiveAppearance,
                sourceMarkdown: store.document.sourceMarkdown,
                changedRegions: store.document.changedRegions,
                unsavedChangedRegions: store.sourceEditingController.unsavedChangedRegions,
                fileURL: store.document.fileURL,
                folderWatchSession: store.folderWatchDispatcher.activeFolderWatchSession
            )
        }
    }
}
