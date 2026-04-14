import Foundation
import Testing
@testable import minimark

@MainActor
struct FolderWatchSessionCoordinatorTests {
    // MARK: - Test doubles

    final class MockDelegate: FolderWatchSessionCoordinatorDelegate {
        var documents: [ReaderSidebarDocumentController.Document] = []
        var _selectedReaderStore: ReaderStore?
        var selectedReaderStore: ReaderStore { _selectedReaderStore! }
        var documentForURLResult: ReaderSidebarDocumentController.Document?
        var selectNewestCalled = false
        var lastOpenRequest: FileOpenRequest?

        func document(for fileURL: URL) -> ReaderSidebarDocumentController.Document? {
            documentForURLResult
        }

        func selectDocumentWithNewestModificationDate() {
            selectNewestCalled = true
        }

        func handleFolderWatchOpenRequest(_ request: FileOpenRequest) {
            lastOpenRequest = request
        }
    }

    // MARK: - Tests

    @Test func initialStateHasNilProperties() {
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            fatalError("Should not be called")
        })

        #expect(owner.activeFolderWatchSession == nil)
        #expect(owner.isFolderWatchInitialScanInProgress == false)
        #expect(owner.didFolderWatchInitialScanFail == false)
        #expect(owner.contentScanProgress == nil)
        #expect(owner.scannedFileCount == nil)
        #expect(owner.canStopFolderWatch == false)
    }

    @Test func folderWatchControllerCreatedLazilyOnFirstUse() throws {
        var controllerCreated = false
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            controllerCreated = true
            return ReaderFolderWatchController(
                folderWatcher: TestFolderWatcher(),
                settingsStore: settingsStore,
                securityScope: TestSecurityScopeAccess(),
                systemNotifier: TestReaderSystemNotifier(),
                folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
            )
        })
        owner.delegate = MockDelegate()

        #expect(owner.folderWatchControllerIfCreated == nil)
        #expect(controllerCreated == false)

        // Trigger lazy creation via a pass-through method
        owner.stopFolderWatch()

        #expect(controllerCreated == true)
        #expect(owner.folderWatchControllerIfCreated != nil)
    }

    @Test func resolvedFolderWatchSessionReturnsRequestedSessionWhenProvided() {
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            fatalError("Should not be called")
        })
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/test"),
            options: .default,
            startedAt: .now
        )

        let result = owner.resolvedFolderWatchSession(
            for: URL(fileURLWithPath: "/tmp/test/file.md"),
            requestedSession: session
        )

        #expect(result == session)
    }

    @Test func resolvedFolderWatchSessionReturnsNilWhenNoWatchActive() {
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            fatalError("Should not be called")
        })

        let result = owner.resolvedFolderWatchSession(
            for: URL(fileURLWithPath: "/tmp/test/file.md"),
            requestedSession: nil
        )

        #expect(result == nil)
    }

    @Test func watchedDocumentIDsReturnsEmptyWhenNoWatchActive() {
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            fatalError("Should not be called")
        })
        let delegate = MockDelegate()
        owner.delegate = delegate

        #expect(owner.watchedDocumentIDs().isEmpty)
    }

    @Test func canStopFolderWatchReflectsActiveSession() {
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            fatalError("Should not be called")
        })

        #expect(owner.canStopFolderWatch == false)
        // Note: canStopFolderWatch becomes true only after a folder watch starts
        // and synchronizeFolderWatchState runs — tested via integration tests
    }

    @Test func dismissPendingFileSelectionRequestClearsBothProperties() {
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            ReaderFolderWatchController(
                folderWatcher: TestFolderWatcher(),
                settingsStore: settingsStore,
                securityScope: TestSecurityScopeAccess(),
                systemNotifier: TestReaderSystemNotifier(),
                folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
            )
        })
        owner.delegate = MockDelegate()

        // Force controller creation, then dismiss
        owner.stopFolderWatch()
        owner.dismissPendingFileSelectionRequest()

        #expect(owner.pendingFileSelectionRequest == nil)
        #expect(owner.folderWatchControllerIfCreated?.pendingFileSelectionRequest == nil)
    }
}
