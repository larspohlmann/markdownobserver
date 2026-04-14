import Foundation
import Observation

@MainActor
@Observable
final class OpenDocumentPathTracker {
    private(set) var openDocumentPaths: Set<String> = []

    func update(from documents: [ReaderSidebarDocumentController.Document]) {
        let paths = Set(documents.compactMap { $0.normalizedFileURL?.path })
        if paths != openDocumentPaths {
            openDocumentPaths = paths
        }
    }
}
