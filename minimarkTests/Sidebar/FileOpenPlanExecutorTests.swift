import Foundation
import Testing
@testable import minimark

@MainActor
struct FileOpenPlanExecutorTests {
    // MARK: - Test doubles

    final class MockDelegate: FileOpenPlanExecutorDelegate {
        var selectedDocumentID: UUID
        var selectedReaderStore: DocumentStore
        var storeConfigurator: ((DocumentStore) -> Void)?
        var selectDocumentCalls: [UUID?] = []
        var bindSelectedStoreCalled = false
        var makeDocumentFactory: () -> SidebarDocumentController.Document

        init(
            selectedDocumentID: UUID,
            selectedReaderStore: DocumentStore,
            makeDocument: @escaping () -> SidebarDocumentController.Document
        ) {
            self.selectedDocumentID = selectedDocumentID
            self.selectedReaderStore = selectedReaderStore
            self.makeDocumentFactory = makeDocument
        }

        func makeDocument() -> SidebarDocumentController.Document {
            makeDocumentFactory()
        }

        func selectDocument(_ documentID: UUID?) {
            selectDocumentCalls.append(documentID)
        }

        func bindSelectedStore() {
            bindSelectedStoreCalled = true
        }

        func resolvedFolderWatchSession(
            for fileURL: URL,
            requestedSession: FolderWatchSession?
        ) -> FolderWatchSession? {
            requestedSession
        }
    }

    // MARK: - Helpers

    private static func makeStore(settingsStore: SettingsStore) -> DocumentStore {
        let settler = AutoOpenSettler(settlingInterval: 1.0)
        let securityScopeResolver = SecurityScopeResolver(
            securityScope: TestSecurityScopeAccess(),
            settingsStore: settingsStore,
            requestWatchedFolderReauthorization: { _ in nil }
        )
        return DocumentStore(
            rendering: RenderingDependencies(
                renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
            ),
            file: FileDependencies(
                watcher: TestFileWatcher(), io: DocumentIOService(), actions: TestReaderFileActions()
            ),
            folderWatch: FolderWatchDependencies(
                autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                settler: settler,
                systemNotifier: TestReaderSystemNotifier()
            ),
            settingsStore: settingsStore,
            securityScopeResolver: securityScopeResolver
        )
    }

    private static func makeHarness() -> (
        executor: FileOpenPlanExecutor,
        delegate: MockDelegate,
        documentList: SidebarDocumentList,
        settingsStore: SettingsStore
    ) {
        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let initialStore = makeStore(settingsStore: settingsStore)
        let initialDocument = SidebarDocumentController.Document(
            id: UUID(), readerStore: initialStore, normalizedFileURL: nil
        )
        let documentList = SidebarDocumentList(initialDocument: initialDocument)
        let observationManager = SidebarObservationManager()
        let rowStateComputer = SidebarRowStateComputer()
        rowStateComputer.rebuildAllRowStates(from: documentList.documents)

        let executor = FileOpenPlanExecutor(
            documentList: documentList,
            observationManager: observationManager,
            rowStateComputer: rowStateComputer
        )

        let delegate = MockDelegate(
            selectedDocumentID: initialDocument.id,
            selectedReaderStore: initialStore,
            makeDocument: {
                SidebarDocumentController.Document(
                    id: UUID(),
                    readerStore: makeStore(settingsStore: settingsStore),
                    normalizedFileURL: nil
                )
            }
        )
        executor.delegate = delegate

        return (executor, delegate, documentList, settingsStore)
    }

    // MARK: - Tests

    @Test func executePlanWithEmptyAssignmentsDoesNothing() {
        let (executor, delegate, documentList, _) = Self.makeHarness()
        let plan = FileOpenPlan(
            assignments: [],
            origin: .manual,
            folderWatchSession: nil,
            materializationStrategy: .loadAll
        )

        executor.executePlan(plan)

        #expect(documentList.documents.count == 1)
        #expect(delegate.bindSelectedStoreCalled == false)
    }

    @Test func executePlanAppendsNewDocumentForCreateNewTarget() throws {
        let (executor, delegate, documentList, _) = Self.makeHarness()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-executor-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        try "# Test".write(to: fileURL, atomically: true, encoding: .utf8)

        let plan = FileOpenPlan(
            assignments: [
                FileOpenPlan.SlotAssignment(
                    fileURL: fileURL,
                    target: .createNew,
                    loadMode: .loadFully,
                    initialDiffBaselineMarkdown: nil
                )
            ],
            origin: .manual,
            folderWatchSession: nil,
            materializationStrategy: .loadAll
        )

        executor.executePlan(plan)

        #expect(documentList.documents.count == 2)
        #expect(delegate.bindSelectedStoreCalled == true)
    }

    @Test func selectDocumentWithNewestModificationDateCallsDelegate() throws {
        let (executor, delegate, documentList, settingsStore) = Self.makeHarness()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-executor-newest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("newest.md")
        try "# Newest".write(to: fileURL, atomically: true, encoding: .utf8)

        // Add a document with a file
        let store = Self.makeStore(settingsStore: settingsStore)
        store.opener.open(at: fileURL, origin: .manual)
        let doc = SidebarDocumentController.Document(
            id: UUID(), readerStore: store, normalizedFileURL: fileURL
        )
        documentList.append(doc)

        executor.selectDocumentWithNewestModificationDate()

        #expect(delegate.selectDocumentCalls.contains(doc.id))
    }
}
