import Foundation
import Testing
@testable import minimark

@MainActor
struct ReaderSidebarGroupingTestHarness {
    let temporaryDirectoryURL: URL
    let documents: [ReaderSidebarDocumentController.Document]

    init(subdirectories: [String], filesPerSubdirectory: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-grouping-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectoryURL = directory

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.grouping.tests.\(UUID().uuidString)"
        )

        var allDocuments: [ReaderSidebarDocumentController.Document] = []

        for subdirectory in subdirectories {
            let subURL = directory.appendingPathComponent(subdirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)

            for i in 0..<filesPerSubdirectory {
                let fileURL = subURL.appendingPathComponent("file\(i).md")
                try "# File \(i)".write(to: fileURL, atomically: true, encoding: .utf8)

                let store = ReaderStore(
                    renderer: TestMarkdownRenderer(),
                    differ: TestChangedRegionDiffer(),
                    fileWatcher: TestFileWatcher(),
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    fileActions: TestReaderFileActions(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                    settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                store.testSetFileURL(fileURL)
                store.testSetFileDisplayName(fileURL.lastPathComponent)

                allDocuments.append(
                    ReaderSidebarDocumentController.Document(id: UUID(), readerStore: store)
                )
            }
        }

        documents = allDocuments
    }

    func documentsInSubdirectory(_ name: String) -> [ReaderSidebarDocumentController.Document] {
        let subURL = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        return documents.filter { doc in
            doc.readerStore.fileURL?.deletingLastPathComponent().path(percentEncoded: false) == subURL.path(percentEncoded: false)
        }
    }

    func directoryPath(for subdirectory: String) -> String {
        temporaryDirectoryURL.appendingPathComponent(subdirectory, isDirectory: true).path(percentEncoded: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}
