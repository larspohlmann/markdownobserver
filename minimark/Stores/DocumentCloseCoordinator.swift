import Foundation

@MainActor
protocol DocumentCloseCoordinatorDelegate: AnyObject {
    typealias Document = SidebarDocumentController.Document

    var selectedDocumentID: UUID { get set }
    var storeConfigurator: ((DocumentStore) -> Void)? { get }
    func makeDocument() -> Document
    func bindSelectedStore()
}

@MainActor
final class DocumentCloseCoordinator {
    typealias Document = SidebarDocumentController.Document

    private let documentList: SidebarDocumentList
    private let observationManager: SidebarObservationManager
    private let rowStateComputer: SidebarRowStateComputer
    weak var delegate: DocumentCloseCoordinatorDelegate?

    init(
        documentList: SidebarDocumentList,
        observationManager: SidebarObservationManager,
        rowStateComputer: SidebarRowStateComputer
    ) {
        self.documentList = documentList
        self.observationManager = observationManager
        self.rowStateComputer = rowStateComputer
    }

    // MARK: - Public API

    func closeDocument(_ documentID: UUID) {
        guard let delegate else { return }
        guard let removed = documentList.remove(documentID: documentID) else {
            return
        }

        if documentList.documents.isEmpty {
            let replacement = delegate.makeDocument()
            documentList.replaceAll(with: [replacement])
            if let storeConfigurator = delegate.storeConfigurator {
                storeConfigurator(replacement.readerStore)
            }
            delegate.selectedDocumentID = replacement.id
            synchronizeAndRebuild()
            delegate.bindSelectedStore()
            return
        }

        if delegate.selectedDocumentID == documentID {
            let nextIndex = min(removed.index, documentList.documents.count - 1)
            delegate.selectedDocumentID = documentList.documents[nextIndex].id
        }

        synchronizeAndRebuild()
        delegate.bindSelectedStore()
    }

    func closeOtherDocuments(keeping documentID: UUID) {
        closeOtherDocuments(keeping: [documentID])
    }

    func closeOtherDocuments(keeping documentIDs: Set<UUID>) {
        guard let delegate else { return }
        let retainedDocuments = documentList.documents.filter { documentIDs.contains($0.id) }
        guard !retainedDocuments.isEmpty else {
            return
        }

        documentList.replaceAll(with: retainedDocuments)

        if !retainedDocuments.contains(where: { $0.id == delegate.selectedDocumentID }) {
            delegate.selectedDocumentID = retainedDocuments[0].id
        }

        synchronizeAndRebuild()
        delegate.bindSelectedStore()
    }

    func closeDocuments(_ documentIDs: Set<UUID>) {
        guard let delegate else { return }
        guard !documentIDs.isEmpty else {
            return
        }

        let removedDocuments = documentList.documents.filter { documentIDs.contains($0.id) }
        guard !removedDocuments.isEmpty else {
            return
        }

        if removedDocuments.count >= documentList.documents.count {
            closeAllDocuments()
            return
        }

        let remainingDocuments = documentList.documents.filter { !documentIDs.contains($0.id) }
        documentList.replaceAll(with: remainingDocuments)

        if !remainingDocuments.contains(where: { $0.id == delegate.selectedDocumentID }) {
            delegate.selectedDocumentID = remainingDocuments[0].id
        }

        synchronizeAndRebuild()
        delegate.bindSelectedStore()
    }

    func closeAllDocuments() {
        guard let delegate else { return }
        let replacement = delegate.makeDocument()
        if let storeConfigurator = delegate.storeConfigurator {
            storeConfigurator(replacement.readerStore)
        }

        documentList.replaceAll(with: [replacement])
        delegate.selectedDocumentID = replacement.id
        synchronizeAndRebuild()
        delegate.bindSelectedStore()
    }

    // MARK: - Private

    private func synchronizeAndRebuild() {
        observationManager.synchronize(
            for: documentList.documents,
            onStoreChanged: makeStoreChangedHandler()
        )
        rowStateComputer.rebuildAllRowStates(from: documentList.documents)
    }

    private func makeStoreChangedHandler() -> @MainActor (UUID) -> Void {
        return { [weak self] documentID in
            guard let self else { return }
            self.rowStateComputer.updateRowStateIfNeeded(
                for: documentID,
                in: self.documentList.documents
            )
        }
    }
}
