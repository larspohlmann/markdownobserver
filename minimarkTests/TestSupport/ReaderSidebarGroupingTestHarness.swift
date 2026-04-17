import Foundation
import Testing
@testable import minimark

@MainActor
struct ReaderSidebarGroupingTestHarness {
    let temporaryDirectoryURL: URL
    let documents: [SidebarDocumentController.Document]

    init(subdirectories: [String], filesPerSubdirectory: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-grouping-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectoryURL = directory

        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.grouping.tests.\(UUID().uuidString)"
        )

        var allDocuments: [SidebarDocumentController.Document] = []

        for subdirectory in subdirectories {
            let subURL = directory.appendingPathComponent(subdirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: subURL, withIntermediateDirectories: true)

            for i in 0..<filesPerSubdirectory {
                let fileURL = subURL.appendingPathComponent("file\(i).md")
                try "# File \(i)".write(to: fileURL, atomically: true, encoding: .utf8)

                let securityScopeResolver = SecurityScopeResolver(
                    securityScope: TestSecurityScopeAccess(),
                    settingsStore: settingsStore,
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                let store = DocumentStore(
                    rendering: RenderingDependencies(
                        renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
                    ),
                    file: FileDependencies(
                        watcher: TestFileWatcher(), io: DocumentIOService(), actions: TestReaderFileActions()
                    ),
                    folderWatch: FolderWatchDependencies(
                        autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                        settler: AutoOpenSettler(settlingInterval: 1.0),
                        systemNotifier: TestReaderSystemNotifier()
                    ),
                    settingsStore: settingsStore,
                    securityScopeResolver: securityScopeResolver
                )
                store.testSetFileURL(fileURL)
                store.testSetFileDisplayName(fileURL.lastPathComponent)

                allDocuments.append(
                    SidebarDocumentController.Document(id: UUID(), readerStore: store)
                )
            }
        }

        documents = allDocuments
    }

    func documentsInSubdirectory(_ name: String) -> [SidebarDocumentController.Document] {
        let subURL = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        return documents.filter { doc in
            doc.readerStore.document.fileURL?.deletingLastPathComponent().path(percentEncoded: false) == subURL.path(percentEncoded: false)
        }
    }

    func directoryPath(for subdirectory: String) -> String {
        temporaryDirectoryURL.appendingPathComponent(subdirectory, isDirectory: true).path(percentEncoded: false)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}
