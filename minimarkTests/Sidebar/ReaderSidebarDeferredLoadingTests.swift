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
        #expect(store.fileLastModifiedAt != nil)
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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        #expect(harness.controller.documents.count == 2)
        for document in harness.controller.documents {
            #expect(!document.readerStore.isDeferredDocument)
            #expect(document.readerStore.fileURL != nil)
            #expect(!document.readerStore.sourceMarkdown.isEmpty)
        }
    }

    @Test @MainActor func selectingDeferredDocumentMaterializesIt() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        // Find the non-selected deferred document
        let deferredDocument = harness.controller.documents.first {
            $0.id != harness.controller.selectedDocumentID
        }!
        #expect(deferredDocument.readerStore.isDeferredDocument)

        // Select it
        harness.controller.selectDocument(deferredDocument.id)

        // Wait for async materialization
        for _ in 0..<5 { await Task.yield() }

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        let countBefore = harness.controller.documents.count

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .manual
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("gamma.md")
        try "# Gamma".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        coordinator.open(FileOpenRequest(
            fileURLs: [thirdFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        let countBefore = harness.controller.documents.count

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session
        ))

        #expect(harness.controller.documents.count == countBefore)
    }

    // MARK: - Regression: external changes to deferred documents

    @Test @MainActor func liveChangeEventFullyLoadsDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))
        await Task.yield()

        // Find the deferred (non-selected) document
        let deferredDocument = harness.controller.documents.first {
            $0.readerStore.isDeferredDocument
        }!
        #expect(deferredDocument.readerStore.sourceMarkdown.isEmpty)

        // Simulate a live folder-watch change event for the deferred file.
        // Use executePlan directly since the coordinator skips existing URLs,
        // but executePlan handles materializing existing deferred documents.
        let deferredFileURL = deferredDocument.readerStore.fileURL!
        harness.controller.executePlan(FileOpenPlan(
            assignments: [FileOpenPlan.SlotAssignment(
                fileURL: deferredFileURL,
                target: .reuseExisting(documentID: deferredDocument.id),
                loadMode: .loadFully,
                initialDiffBaselineMarkdown: "# Old content"
            )],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .loadAll
        ))
        for _ in 0..<5 { await Task.yield() }

        // The deferred document should now be fully loaded
        #expect(!deferredDocument.readerStore.isDeferredDocument)
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func liveChangeEventShowsIndicatorForDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))
        await Task.yield()

        let deferredDocument = harness.controller.documents.first {
            $0.readerStore.isDeferredDocument
        }!

        // Simulate a live change with a diff baseline (file was modified).
        let deferredFileURL = deferredDocument.readerStore.fileURL!
        harness.controller.executePlan(FileOpenPlan(
            assignments: [FileOpenPlan.SlotAssignment(
                fileURL: deferredFileURL,
                target: .reuseExisting(documentID: deferredDocument.id),
                loadMode: .loadFully,
                initialDiffBaselineMarkdown: "# Old content"
            )],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .loadAll
        ))
        for _ in 0..<5 { await Task.yield() }

        // The yellow change indicator should be visible
        #expect(deferredDocument.readerStore.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func liveAddEventDoesNotShowIndicatorForDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))
        await Task.yield()

        let deferredDocument = harness.controller.documents.first {
            $0.readerStore.isDeferredDocument
        }!

        // Simulate a live event without a diff baseline (new file, not a modification).
        let deferredFileURL = deferredDocument.readerStore.fileURL!
        harness.controller.executePlan(FileOpenPlan(
            assignments: [FileOpenPlan.SlotAssignment(
                fileURL: deferredFileURL,
                target: .reuseExisting(documentID: deferredDocument.id),
                loadMode: .loadFully,
                initialDiffBaselineMarkdown: nil
            )],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .loadAll
        ))
        for _ in 0..<5 { await Task.yield() }

        // No yellow indicator — this wasn't a modification
        #expect(!deferredDocument.readerStore.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func materializeDeferredDocumentWorksFromLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        store.transitionToLoading()
        #expect(store.documentLoadState == .loading)

        store.materializeDeferredDocument()

        #expect(store.documentLoadState == .ready || store.documentLoadState == .settlingAutoOpen)
        #expect(!store.sourceMarkdown.isEmpty)
        #expect(!store.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func selectingDeferredDocumentSetsLoadingStateImmediately() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        let deferredDocument = harness.controller.documents.first {
            $0.id != harness.controller.selectedDocumentID
        }!
        #expect(deferredDocument.readerStore.documentLoadState == .deferred)

        harness.controller.selectDocument(deferredDocument.id)

        // Immediately after selectDocument: state should be .loading, not yet fully loaded
        #expect(deferredDocument.readerStore.documentLoadState == .loading)
        #expect(deferredDocument.readerStore.sourceMarkdown.isEmpty)

        // After yielding: the Task completes and the document content is loaded.
        // State may still be .loading due to holdLoadingOverlayBriefly() keeping the
        // overlay visible for the WKWebView to render.
        for _ in 0..<5 { await Task.yield() }
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func transitionToLoadingSetsLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        #expect(store.documentLoadState == .deferred)

        store.transitionToLoading()

        #expect(store.documentLoadState == .loading)
    }

    @Test @MainActor func replaceSelectedSlotLoadsContentSynchronously() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.selectedReaderStore

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        // Content is loaded synchronously via executePlan
        #expect(!store.sourceMarkdown.isEmpty)
        #expect(store.fileURL?.lastPathComponent == "alpha.md")
    }
}
