import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct OpenDocumentPathTrackerTests {
    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "path-tracker-tests.\(UUID().uuidString)"
        )
    }

    @MainActor
    private func makeDocument(
        normalizedURL: URL? = nil,
        settingsStore: SettingsStore
    ) -> SidebarDocumentController.Document {
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
            securityScopeResolver: SecurityScopeResolver(
                securityScope: TestSecurityScopeAccess(),
                settingsStore: settingsStore,
                requestWatchedFolderReauthorization: { _ in nil }
            )
        )
        return SidebarDocumentController.Document(
            id: UUID(), readerStore: store, normalizedFileURL: normalizedURL
        )
    }

    @Test @MainActor
    func updateSetsPathsFromDocuments() {
        let settings = makeSettingsStore()
        let tracker = OpenDocumentPathTracker()
        let urlA = URL(fileURLWithPath: "/tmp/a.md")
        let urlB = URL(fileURLWithPath: "/tmp/b.md")
        let docs = [
            makeDocument(normalizedURL: urlA, settingsStore: settings),
            makeDocument(normalizedURL: urlB, settingsStore: settings),
        ]

        tracker.update(from: docs)

        #expect(tracker.openDocumentPaths == Set(["/tmp/a.md", "/tmp/b.md"]))
    }

    @Test @MainActor
    func updateSkipsDocumentsWithNilURL() {
        let settings = makeSettingsStore()
        let tracker = OpenDocumentPathTracker()
        let url = URL(fileURLWithPath: "/tmp/a.md")
        let docs = [
            makeDocument(normalizedURL: url, settingsStore: settings),
            makeDocument(settingsStore: settings),
        ]

        tracker.update(from: docs)

        #expect(tracker.openDocumentPaths == Set(["/tmp/a.md"]))
    }

    @Test @MainActor
    func updateClearsPreviousPathsOnNewList() {
        let settings = makeSettingsStore()
        let tracker = OpenDocumentPathTracker()

        let urlA = URL(fileURLWithPath: "/tmp/a.md")
        tracker.update(from: [makeDocument(normalizedURL: urlA, settingsStore: settings)])
        #expect(tracker.openDocumentPaths == Set(["/tmp/a.md"]))

        let urlB = URL(fileURLWithPath: "/tmp/b.md")
        tracker.update(from: [makeDocument(normalizedURL: urlB, settingsStore: settings)])
        #expect(tracker.openDocumentPaths == Set(["/tmp/b.md"]))
    }
}
