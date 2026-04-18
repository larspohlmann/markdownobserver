import Foundation

/// Routes `ContentViewAction` cases that concern the active document:
/// opens, editing-flow mutations, TOC updates, and appearance lock.
@MainActor
final class DocumentActionRouter {
    private let documentOpen: WindowDocumentOpenCoordinator
    private let appearanceLock: AppearanceLockCoordinator
    private let sidebarDocumentController: SidebarDocumentController

    init(
        documentOpen: WindowDocumentOpenCoordinator,
        appearanceLock: AppearanceLockCoordinator,
        sidebarDocumentController: SidebarDocumentController
    ) {
        self.documentOpen = documentOpen
        self.appearanceLock = appearanceLock
        self.sidebarDocumentController = sidebarDocumentController
    }

    func requestFileOpen(_ request: FileOpenRequest) {
        documentOpen.openFileRequest(request)
    }

    func toggleAppearanceLock() {
        appearanceLock.toggleLock()
    }

    func saveSourceDraft() {
        sidebarDocumentController.selectedDocumentStore.editingFlow.save()
    }

    func discardSourceDraft() {
        sidebarDocumentController.selectedDocumentStore.editingFlow.discard()
    }

    func startSourceEditing() {
        sidebarDocumentController.selectedDocumentStore.editingFlow.startEditing()
    }

    func updateSourceDraft(_ markdown: String) {
        sidebarDocumentController.selectedDocumentStore.editingFlow.updateDraft(markdown)
    }

    func grantImageDirectoryAccess(_ url: URL) {
        sidebarDocumentController.selectedDocumentStore.persister.grantImageDirectoryAccess(folderURL: url)
    }

    func openInApplication(_ app: ExternalApplication?) {
        sidebarDocumentController.selectedDocumentStore.document.openInApplication(app)
    }

    func revealInFinder() {
        sidebarDocumentController.selectedDocumentStore.document.revealInFinder()
    }

    func presentError(_ error: Error) {
        sidebarDocumentController.selectedDocumentStore.document.handle(error)
    }

    func updateTOCHeadings(_ headings: [TOCHeading]) {
        sidebarDocumentController.selectedDocumentStore.toc.updateHeadings(headings)
    }
}
