import Foundation
import Observation

@MainActor
@Observable
final class SidebarDocumentList {
    typealias Document = ReaderSidebarDocumentController.Document

    private(set) var documents: [Document]
    @ObservationIgnored private var documentsByNormalizedURL: [URL: UUID] = [:]

    init(initialDocument: Document) {
        documents = [initialDocument]
        rebuildIndex()
    }

    func append(_ document: Document) {
        documents.append(document)
        indexDocument(document)
    }

    @discardableResult
    func remove(documentID: UUID) -> (index: Int, document: Document)? {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else {
            return nil
        }
        let document = documents[index]
        unindexDocument(document)
        documents.remove(at: index)
        return (index, document)
    }

    func replaceAll(with newDocuments: [Document]) {
        documents = newDocuments
        rebuildIndex()
    }

    func updateNormalizedURL(for documentID: UUID, to url: URL?) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else { return }
        unindexDocument(documents[index])
        let normalized = url.map(FileRouting.normalizedFileURL)
        documents[index].normalizedFileURL = normalized
        if let normalized {
            documentsByNormalizedURL[normalized] = documentID
        }
    }

    func document(for fileURL: URL) -> Document? {
        let normalized = FileRouting.normalizedFileURL(fileURL)
        guard let documentID = documentsByNormalizedURL[normalized] else { return nil }
        return documents.first(where: { $0.id == documentID })
    }

    func contains(documentID: UUID) -> Bool {
        documents.contains(where: { $0.id == documentID })
    }

    func orderedDocuments(matching documentIDs: Set<UUID>) -> [Document] {
        documents.filter { documentIDs.contains($0.id) }
    }

    // MARK: - Private

    private func rebuildIndex() {
        documentsByNormalizedURL = [:]
        for document in documents {
            if let url = document.normalizedFileURL {
                documentsByNormalizedURL[FileRouting.normalizedFileURL(url)] = document.id
            }
        }
    }

    private func indexDocument(_ document: Document) {
        if let url = document.normalizedFileURL {
            documentsByNormalizedURL[FileRouting.normalizedFileURL(url)] = document.id
        }
    }

    private func unindexDocument(_ document: Document) {
        if let url = document.normalizedFileURL {
            documentsByNormalizedURL.removeValue(forKey: FileRouting.normalizedFileURL(url))
        }
    }
}
