import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct SidebarDocumentListTests {
    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "doc-list-tests.\(UUID().uuidString)"
        )
    }

    @MainActor
    private func makeDocument(
        id: UUID = UUID(),
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
            id: id, readerStore: store, normalizedFileURL: normalizedURL
        )
    }

    // MARK: - Append

    @Test @MainActor func appendAddsDocumentAndIndexesURL() {
        let settings = makeSettingsStore()
        let initial = makeDocument(settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: initial)

        let url = URL(fileURLWithPath: "/tmp/test.md")
        let doc = makeDocument(normalizedURL: url, settingsStore: settings)
        list.append(doc)

        #expect(list.documents.count == 2)
        #expect(list.document(for: url)?.id == doc.id)
    }

    // MARK: - Remove

    @Test @MainActor func removeReturnsRemovedDocumentAndUpdatesIndex() {
        let settings = makeSettingsStore()
        let url = URL(fileURLWithPath: "/tmp/alpha.md")
        let initial = makeDocument(normalizedURL: url, settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: initial)

        let result = list.remove(documentID: initial.id)

        #expect(result?.index == 0)
        #expect(result?.document.id == initial.id)
        #expect(list.documents.isEmpty)
        #expect(list.document(for: url) == nil)
    }

    @Test @MainActor func removeNonexistentReturnsNil() {
        let settings = makeSettingsStore()
        let list = SidebarDocumentList(initialDocument: makeDocument(settingsStore: settings))

        let result = list.remove(documentID: UUID())

        #expect(result == nil)
    }

    // MARK: - Lookup

    @Test @MainActor func documentForURLReturnsCorrectDocument() {
        let settings = makeSettingsStore()
        let urlA = URL(fileURLWithPath: "/tmp/a.md")
        let urlB = URL(fileURLWithPath: "/tmp/b.md")
        let initial = makeDocument(normalizedURL: urlA, settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: initial)
        let docB = makeDocument(normalizedURL: urlB, settingsStore: settings)
        list.append(docB)

        #expect(list.document(for: urlA)?.id == initial.id)
        #expect(list.document(for: urlB)?.id == docB.id)
    }

    @Test @MainActor func documentForUnknownURLReturnsNil() {
        let settings = makeSettingsStore()
        let list = SidebarDocumentList(initialDocument: makeDocument(settingsStore: settings))

        #expect(list.document(for: URL(fileURLWithPath: "/tmp/nope.md")) == nil)
    }

    // MARK: - Replace all

    @Test @MainActor func replaceAllRebuildsIndex() {
        let settings = makeSettingsStore()
        let urlOld = URL(fileURLWithPath: "/tmp/old.md")
        let initial = makeDocument(normalizedURL: urlOld, settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: initial)

        let urlNew = URL(fileURLWithPath: "/tmp/new.md")
        let replacement = makeDocument(normalizedURL: urlNew, settingsStore: settings)
        list.replaceAll(with: [replacement])

        #expect(list.documents.count == 1)
        #expect(list.document(for: urlNew)?.id == replacement.id)
        #expect(list.document(for: urlOld) == nil)
    }

    // MARK: - Update URL

    @Test @MainActor func updateNormalizedURLUpdatesIndex() {
        let settings = makeSettingsStore()
        let oldURL = URL(fileURLWithPath: "/tmp/old.md")
        let doc = makeDocument(normalizedURL: oldURL, settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: doc)

        let newURL = URL(fileURLWithPath: "/tmp/new.md")
        list.updateNormalizedURL(for: doc.id, to: newURL)

        #expect(list.document(for: newURL)?.id == doc.id)
        #expect(list.document(for: oldURL) == nil)
    }

    @Test @MainActor func updateNormalizedURLToNilRemovesFromIndex() {
        let settings = makeSettingsStore()
        let url = URL(fileURLWithPath: "/tmp/existing.md")
        let doc = makeDocument(normalizedURL: url, settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: doc)

        list.updateNormalizedURL(for: doc.id, to: nil)

        #expect(list.document(for: url) == nil)
        #expect(list.documents.first?.normalizedFileURL == nil)
    }

    // MARK: - Ordered documents

    @Test @MainActor func orderedDocumentsPreservesInsertionOrder() {
        let settings = makeSettingsStore()
        let docA = makeDocument(settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: docA)
        let docB = makeDocument(settingsStore: settings)
        let docC = makeDocument(settingsStore: settings)
        list.append(docB)
        list.append(docC)

        let matching = list.orderedDocuments(matching: [docC.id, docA.id])

        #expect(matching.map(\.id) == [docA.id, docC.id])
    }

    // MARK: - Contains

    @Test @MainActor func containsReturnsTrueForExistingDocument() {
        let settings = makeSettingsStore()
        let doc = makeDocument(settingsStore: settings)
        let list = SidebarDocumentList(initialDocument: doc)

        #expect(list.contains(documentID: doc.id))
        #expect(!list.contains(documentID: UUID()))
    }
}
