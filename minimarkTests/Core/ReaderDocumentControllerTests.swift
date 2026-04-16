import Testing
import Foundation
@testable import minimark

@MainActor
@Suite("ReaderDocumentController")
struct ReaderDocumentControllerTests {
    private func makeSUT(
        io: ReaderDocumentIO = ReaderDocumentIOService(),
        watcher: FileChangeWatching = TestFileWatcher(),
        fileActions: ReaderFileActionHandling = TestReaderFileActions()
    ) -> ReaderDocumentController {
        let settings = TestReaderSettingsStore(autoRefreshOnExternalChange: true)
        return ReaderDocumentController(
            fileDependencies: ReaderFileDependencies(watcher: watcher, io: io, actions: fileActions),
            settingsStore: settings,
            settler: ReaderAutoOpenSettler(settlingInterval: 1.0)
        )
    }

    @Test("initial state is empty")
    func initialStateIsEmpty() {
        let sut = makeSUT()
        #expect(sut.fileURL == nil)
        #expect(sut.fileDisplayName.isEmpty)
        #expect(sut.documentLoadState == .ready)
        #expect(!sut.isCurrentFileMissing)
        #expect(sut.lastError == nil)
        #expect(!sut.hasOpenDocument)
    }

    @Test("presentLoadedState sets document identity and content")
    func presentLoadedStateSetsState() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let now = Date()
        sut.presentLoadedState(
            markdown: "# Hello",
            modificationDate: now,
            at: url,
            changedRegions: []
        )
        #expect(sut.fileURL == url)
        #expect(sut.fileDisplayName == "test.md")
        #expect(sut.sourceMarkdown == "# Hello")
        #expect(sut.savedMarkdown == "# Hello")
        #expect(sut.fileLastModifiedAt == now)
        #expect(sut.hasOpenDocument)
    }

    @Test("presentMissingDocument sets error state")
    func presentMissingDocumentSetsError() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/missing.md")
        sut.presentMissingDocument(
            at: url,
            error: ReaderError.noOpenFileInReader
        )
        #expect(sut.isCurrentFileMissing)
        #expect(sut.lastError != nil)
        #expect(sut.fileURL == url)
    }

    @Test("clearOpenDocument resets all state")
    func clearOpenDocumentResetsState() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        sut.presentLoadedState(
            markdown: "# Hello",
            modificationDate: Date(),
            at: url,
            changedRegions: []
        )
        sut.clearOpenDocument()
        #expect(sut.fileURL == nil)
        #expect(sut.fileDisplayName.isEmpty)
        #expect(!sut.hasOpenDocument)
    }

    @Test("deferFile sets deferred load state")
    func deferFileSetsState() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/deferred.md")
        sut.deferFile(at: url, origin: .folderWatchInitialBatchAutoOpen)
        #expect(sut.fileURL != nil)
        #expect(sut.documentLoadState == .deferred)
        #expect(sut.isDeferredDocument)
    }

    @Test("transitionToLoading changes state from deferred")
    func transitionToLoadingFromDeferred() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/test.md")
        sut.deferFile(at: url, origin: .folderWatchInitialBatchAutoOpen)
        sut.transitionToLoading()
        #expect(sut.documentLoadState == .loading)
    }

    @Test("handle sets lastError")
    func handleSetsError() {
        let sut = makeSUT()
        sut.handle(ReaderError.noOpenFileInReader)
        #expect(sut.lastError != nil)
    }

    @Test("clearLastError clears error")
    func clearLastErrorClears() {
        let sut = makeSUT()
        sut.handle(ReaderError.noOpenFileInReader)
        sut.clearLastError()
        #expect(sut.lastError == nil)
    }

    @Test("windowTitle includes file name when document is open")
    func windowTitleIncludesFileName() {
        let sut = makeSUT()
        let url = URL(fileURLWithPath: "/tmp/readme.md")
        sut.presentLoadedState(
            markdown: "# Test",
            modificationDate: Date(),
            at: url,
            changedRegions: []
        )
        #expect(sut.windowTitle.contains("readme.md"))
    }

    @Test("windowTitle shows app name when no document")
    func windowTitleShowsAppName() {
        let sut = makeSUT()
        #expect(sut.windowTitle == ReaderWindowTitleFormatter.appName)
    }
}
