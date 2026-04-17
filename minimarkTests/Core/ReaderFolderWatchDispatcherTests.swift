import Testing
import Foundation
@testable import minimark

@MainActor
@Suite("ReaderFolderWatchDispatcher")
struct ReaderFolderWatchDispatcherTests {
    private func makeSUT() -> ReaderFolderWatchDispatcher {
        ReaderFolderWatchDispatcher(
            folderWatchDependencies: ReaderFolderWatchDependencies(
                autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                systemNotifier: TestReaderSystemNotifier()
            )
        )
    }

    @Test("setSession updates activeFolderWatchSession")
    func setSessionUpdatesSession() {
        let sut = makeSUT()
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/test"),
            options: .default,
            startedAt: Date()
        )
        sut.setSession(session)
        #expect(sut.activeFolderWatchSession != nil)
    }

    @Test("dismissAutoOpenWarning clears warning")
    func dismissAutoOpenWarningClears() {
        let sut = makeSUT()
        sut.dismissAutoOpenWarning()
        #expect(sut.autoOpenWarning == nil)
    }

    @Test("isWatchingFolder reflects session state")
    func isWatchingFolderReflectsSession() {
        let sut = makeSUT()
        #expect(!sut.isWatchingFolder)
        sut.setSession(ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/test"),
            options: .default,
            startedAt: Date()
        ))
        #expect(sut.isWatchingFolder)
    }
}
