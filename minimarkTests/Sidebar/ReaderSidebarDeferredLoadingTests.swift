import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderSidebarDeferredLoadingTests {
    @Test @MainActor func deferFileSetsURLAndDisplayNameWithoutLoadingContent() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)

        #expect(store.fileURL?.path == harness.primaryFileURL.path)
        #expect(store.fileDisplayName == "alpha.md")
        #expect(store.documentLoadState == .deferred)
        #expect(store.sourceMarkdown.isEmpty)
        #expect(store.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func materializeDeferredDocumentLoadsContentAndStartsWatcher() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        #expect(store.isDeferredDocument)

        store.materializeDeferredDocument()

        #expect(!store.isDeferredDocument)
        #expect(store.documentLoadState == .ready || store.documentLoadState == .settlingAutoOpen)
        #expect(!store.sourceMarkdown.isEmpty)
        #expect(!store.renderedHTMLDocument.isEmpty)
        #expect(store.fileURL?.path == harness.primaryFileURL.path)
        #expect(harness.fileWatchers[0].startCallCount == 1)
    }

    @Test @MainActor func materializeDeferredDocumentHandlesMissingFile() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let missingURL = harness.temporaryDirectoryURL.appendingPathComponent("gone.md")
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: missingURL, folderWatchSession: session)
        store.materializeDeferredDocument()

        #expect(store.lastError != nil || store.fileURL?.path == missingURL.path)
    }

    @Test @MainActor func burstOpenWithFolderWatchOriginCreatesDeferredDocuments() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        #expect(harness.controller.documents.count == 2)
        // The non-selected document should be deferred
        let nonSelectedDocuments = harness.controller.documents.filter {
            $0.id != harness.controller.selectedDocumentID
        }
        for document in nonSelectedDocuments {
            #expect(document.readerStore.isDeferredDocument)
            #expect(document.readerStore.sourceMarkdown.isEmpty)
        }
        // The selected document should have been materialized
        #expect(!harness.controller.selectedReaderStore.isDeferredDocument)
    }

    @Test @MainActor func burstOpenWithManualOriginLoadsAllDocumentsFully() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        #expect(harness.controller.documents.count == 2)
        for document in harness.controller.documents {
            #expect(!document.readerStore.isDeferredDocument)
            #expect(document.readerStore.fileURL != nil)
            #expect(!document.readerStore.sourceMarkdown.isEmpty)
        }
    }

    @Test @MainActor func selectingDeferredDocumentMaterializesIt() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        // Find the non-selected deferred document
        let deferredDocument = harness.controller.documents.first {
            $0.id != harness.controller.selectedDocumentID
        }!
        #expect(deferredDocument.readerStore.isDeferredDocument)

        // Select it
        harness.controller.selectDocument(deferredDocument.id)

        // Now it should be fully loaded
        #expect(!deferredDocument.readerStore.isDeferredDocument)
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func openingAlreadyDeferredDocumentDoesNotDuplicate() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        let countBefore = harness.controller.documents.count

        harness.controller.openAdditionalDocument(
            at: harness.secondaryFileURL,
            origin: .manual
        )

        #expect(harness.controller.documents.count == countBefore)
    }

    @Test @MainActor func openDocumentInSelectedSlotOnDeferredDocumentReplacesCleanly() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("gamma.md")
        try "# Gamma".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        harness.controller.openDocumentInSelectedSlot(at: thirdFileURL, origin: .manual)

        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "gamma.md")
        #expect(!harness.controller.selectedReaderStore.isDeferredDocument)
        #expect(!harness.controller.selectedReaderStore.sourceMarkdown.isEmpty)
    }

    @Test @MainActor func liveFolderWatchEventForDeferredDocumentDoesNotDuplicate() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        let countBefore = harness.controller.documents.count

        harness.controller.openDocumentsBurst(
            at: [harness.secondaryFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session
        )

        #expect(harness.controller.documents.count == countBefore)
    }
}
