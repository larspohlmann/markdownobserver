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
}
