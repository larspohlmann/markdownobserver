import Foundation
import Testing
@testable import minimark

@MainActor
struct DocumentCloseCoordinatorTests {
    // MARK: - Test doubles

    final class MockDelegate: DocumentCloseCoordinatorDelegate {
        var selectedDocumentID: UUID
        var storeConfigurator: ((ReaderStore) -> Void)?
        var bindSelectedStoreCalled = false
        let makeDocumentFactory: () -> ReaderSidebarDocumentController.Document

        init(
            selectedDocumentID: UUID,
            makeDocument: @escaping () -> ReaderSidebarDocumentController.Document
        ) {
            self.selectedDocumentID = selectedDocumentID
            self.makeDocumentFactory = makeDocument
        }

        func makeDocument() -> ReaderSidebarDocumentController.Document {
            makeDocumentFactory()
        }

        func bindSelectedStore() {
            bindSelectedStoreCalled = true
        }
    }

    // MARK: - Helpers

    private static func makeStore(settingsStore: ReaderSettingsStore) -> ReaderStore {
        let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
        let securityScopeResolver = SecurityScopeResolver(
            securityScope: TestSecurityScopeAccess(),
            settingsStore: settingsStore,
            requestWatchedFolderReauthorization: { _ in nil }
        )
        return ReaderStore(
            rendering: RenderingDependencies(
                renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
            ),
            file: FileDependencies(
                watcher: TestFileWatcher(), io: ReaderDocumentIOService(), actions: TestReaderFileActions()
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

    private static func makeDocument(settingsStore: ReaderSettingsStore) -> ReaderSidebarDocumentController.Document {
        ReaderSidebarDocumentController.Document(
            id: UUID(),
            readerStore: makeStore(settingsStore: settingsStore),
            normalizedFileURL: nil
        )
    }

    private static func makeHarness(documentCount: Int = 1) -> (
        coordinator: DocumentCloseCoordinator,
        delegate: MockDelegate,
        documentList: SidebarDocumentList
    ) {
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let initialDocument = makeDocument(settingsStore: settingsStore)
        let documentList = SidebarDocumentList(initialDocument: initialDocument)

        for _ in 1..<documentCount {
            documentList.append(makeDocument(settingsStore: settingsStore))
        }

        let coordinator = DocumentCloseCoordinator(
            documentList: documentList,
            observationManager: SidebarObservationManager(),
            rowStateComputer: SidebarRowStateComputer()
        )

        let delegate = MockDelegate(
            selectedDocumentID: initialDocument.id,
            makeDocument: { makeDocument(settingsStore: settingsStore) }
        )
        coordinator.delegate = delegate

        return (coordinator, delegate, documentList)
    }

    // MARK: - Tests

    @Test func closeLastDocumentCreatesReplacement() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 1)
        let originalID = documentList.documents[0].id

        coordinator.closeDocument(originalID)

        #expect(documentList.documents.count == 1)
        #expect(documentList.documents[0].id != originalID)
        #expect(delegate.selectedDocumentID == documentList.documents[0].id)
        #expect(delegate.bindSelectedStoreCalled)
    }

    @Test func closeDocumentRemovesFromList() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 3)
        _ = delegate  // prevent deallocation of weak delegate
        let idToRemove = documentList.documents[1].id

        coordinator.closeDocument(idToRemove)

        #expect(documentList.documents.count == 2)
        #expect(!documentList.documents.contains(where: { $0.id == idToRemove }))
    }

    @Test func closeSelectedDocumentUpdatesSelection() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 3)
        let selectedID = documentList.documents[1].id
        delegate.selectedDocumentID = selectedID

        coordinator.closeDocument(selectedID)

        #expect(delegate.selectedDocumentID != selectedID)
        #expect(documentList.documents.contains(where: { $0.id == delegate.selectedDocumentID }))
    }

    @Test func closeOtherDocumentsRetainsSpecified() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 3)
        let keepID = documentList.documents[1].id
        delegate.selectedDocumentID = keepID

        coordinator.closeOtherDocuments(keeping: keepID)

        #expect(documentList.documents.count == 1)
        #expect(documentList.documents[0].id == keepID)
        #expect(delegate.selectedDocumentID == keepID)
    }

    @Test func closeAllDocumentsCreatesReplacement() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 3)

        coordinator.closeAllDocuments()

        #expect(documentList.documents.count == 1)
        #expect(delegate.selectedDocumentID == documentList.documents[0].id)
        #expect(delegate.bindSelectedStoreCalled)
    }

    @Test func closeDocumentsWithSetRemovesMultiple() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 4)
        _ = delegate  // prevent deallocation of weak delegate
        let idsToRemove: Set<UUID> = [documentList.documents[1].id, documentList.documents[2].id]

        coordinator.closeDocuments(idsToRemove)

        #expect(documentList.documents.count == 2)
        for id in idsToRemove {
            #expect(!documentList.documents.contains(where: { $0.id == id }))
        }
    }

    @Test func closeDocumentsWithAllDocumentsCreatesReplacement() {
        let (coordinator, delegate, documentList) = Self.makeHarness(documentCount: 2)
        let allIDs = Set(documentList.documents.map(\.id))

        coordinator.closeDocuments(allIDs)

        #expect(documentList.documents.count == 1)
        #expect(!allIDs.contains(delegate.selectedDocumentID))
        #expect(delegate.bindSelectedStoreCalled)
    }
}
