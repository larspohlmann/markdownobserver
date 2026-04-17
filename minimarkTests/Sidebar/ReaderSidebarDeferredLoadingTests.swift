import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderSidebarDeferredLoadingTests {
    @Test @MainActor func deferFileSetsURLAndDisplayNameWithoutLoadingContent() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = FolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.opener.deferFile(at: harness.primaryFileURL, folderWatchSession: session)

        #expect(store.document.fileURL?.path == harness.primaryFileURL.path)
        #expect(store.document.fileDisplayName == "alpha.md")
        #expect(store.document.documentLoadState == .deferred)
        #expect(store.document.sourceMarkdown.isEmpty)
        #expect(store.renderingController.renderedHTMLDocument.isEmpty)
        #expect(store.document.fileLastModifiedAt != nil)
    }

    @Test @MainActor func materializeDeferredDocumentLoadsContentAndStartsWatcher() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = FolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.opener.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        #expect(store.document.isDeferredDocument)

        store.opener.materializeDeferred()

        #expect(!store.document.isDeferredDocument)
        #expect(store.document.documentLoadState == .ready || store.document.documentLoadState == .settlingAutoOpen)
        #expect(!store.document.sourceMarkdown.isEmpty)
        #expect(!store.renderingController.renderedHTMLDocument.isEmpty)
        #expect(store.document.fileURL?.path == harness.primaryFileURL.path)
        #expect(harness.fileWatchers[0].startCallCount == 1)
    }

    @Test @MainActor func materializeDeferredDocumentHandlesMissingFile() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let missingURL = harness.temporaryDirectoryURL.appendingPathComponent("gone.md")
        let session = FolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.opener.deferFile(at: missingURL, folderWatchSession: session)
        store.opener.materializeDeferred()

        #expect(store.document.lastError != nil || store.document.fileURL?.path == missingURL.path)
    }

    @Test @MainActor func burstOpenWithFolderWatchOriginCreatesDeferredDocuments() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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
            #expect(document.readerStore.document.isDeferredDocument)
            #expect(document.readerStore.document.sourceMarkdown.isEmpty)
        }
        // The selected document should have been materialized
        #expect(!harness.controller.selectedReaderStore.document.isDeferredDocument)
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
            #expect(!document.readerStore.document.isDeferredDocument)
            #expect(document.readerStore.document.fileURL != nil)
            #expect(!document.readerStore.document.sourceMarkdown.isEmpty)
        }
    }

    @Test @MainActor func selectingDeferredDocumentMaterializesIt() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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
        #expect(deferredDocument.readerStore.document.isDeferredDocument)

        // Select it
        harness.controller.selectDocument(deferredDocument.id)

        // Wait for async materialization
        for _ in 0..<5 { await Task.yield() }

        // Now it should be fully loaded
        #expect(!deferredDocument.readerStore.document.isDeferredDocument)
        #expect(!deferredDocument.readerStore.document.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderingController.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func openingAlreadyDeferredDocumentDoesNotDuplicate() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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

        let session = FolderWatchSession(
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

        #expect(harness.controller.selectedReaderStore.document.fileURL?.lastPathComponent == "gamma.md")
        #expect(!harness.controller.selectedReaderStore.document.isDeferredDocument)
        #expect(!harness.controller.selectedReaderStore.document.sourceMarkdown.isEmpty)
    }

    @Test @MainActor func liveFolderWatchEventForDeferredDocumentDoesNotDuplicate() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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

        let session = FolderWatchSession(
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
            $0.readerStore.document.isDeferredDocument
        }!
        #expect(deferredDocument.readerStore.document.sourceMarkdown.isEmpty)

        // Simulate a live folder-watch change event for the deferred file.
        // Use executePlan directly so this test can provide a one-off plan
        // that reuses the existing deferred document, forces .loadFully,
        // and supplies a specific diff baseline for the change event.
        let deferredFileURL = deferredDocument.readerStore.document.fileURL!
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
        #expect(!deferredDocument.readerStore.document.isDeferredDocument)
        #expect(!deferredDocument.readerStore.document.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderingController.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func liveChangeEventShowsIndicatorForDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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
            $0.readerStore.document.isDeferredDocument
        }!

        // Simulate a live change with a diff baseline (file was modified).
        let deferredFileURL = deferredDocument.readerStore.document.fileURL!
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
        #expect(deferredDocument.readerStore.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func liveAddEventDoesNotShowIndicatorForDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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
            $0.readerStore.document.isDeferredDocument
        }!

        // Simulate a live event without a diff baseline (new file, not a modification).
        let deferredFileURL = deferredDocument.readerStore.document.fileURL!
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
        #expect(!deferredDocument.readerStore.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func materializeDeferredDocumentWorksFromLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = FolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.opener.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        store.document.transitionToLoading()
        #expect(store.document.documentLoadState == .loading)

        store.opener.materializeDeferred()

        #expect(store.document.documentLoadState == .ready || store.document.documentLoadState == .settlingAutoOpen)
        #expect(!store.document.sourceMarkdown.isEmpty)
        #expect(!store.renderingController.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func selectingDeferredDocumentSetsLoadingStateImmediately() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = FolderWatchSession(
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
        #expect(deferredDocument.readerStore.document.documentLoadState == .deferred)

        harness.controller.selectDocument(deferredDocument.id)

        // Immediately after selectDocument: state should be .loading, not yet fully loaded
        #expect(deferredDocument.readerStore.document.documentLoadState == .loading)
        #expect(deferredDocument.readerStore.document.sourceMarkdown.isEmpty)

        // After yielding: the Task completes and the document content is loaded.
        // State may still be .loading due to holdLoadingOverlayBriefly() keeping the
        // overlay visible for the WKWebView to render.
        for _ in 0..<5 { await Task.yield() }
        #expect(!deferredDocument.readerStore.document.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderingController.renderedHTMLDocument.isEmpty)
    }

    @Test @MainActor func transitionToLoadingSetsLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = FolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.opener.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        #expect(store.document.documentLoadState == .deferred)

        store.document.transitionToLoading()

        #expect(store.document.documentLoadState == .loading)
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
        #expect(!store.document.sourceMarkdown.isEmpty)
        #expect(store.document.fileURL?.lastPathComponent == "alpha.md")
    }
}
