import Foundation
import Testing
@testable import minimark

@MainActor
struct FolderWatchSessionCoordinatorTests {
    // MARK: - Test doubles

    final class MockDelegate: FolderWatchSessionCoordinatorDelegate {
        var documents: [SidebarDocumentController.Document] = []
        var _selectedReaderStore: DocumentStore?
        var selectedReaderStore: DocumentStore { _selectedReaderStore! }
        var documentForURLResult: SidebarDocumentController.Document?
        var selectNewestCalled = false
        var lastOpenRequest: FileOpenRequest?

        func document(for fileURL: URL) -> SidebarDocumentController.Document? {
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
        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            controllerCreated = true
            return FolderWatchController(
                folderWatcher: TestFolderWatcher(),
                settingsStore: settingsStore,
                securityScope: TestSecurityScopeAccess(),
                systemNotifier: TestReaderSystemNotifier(),
                folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
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
        let session = FolderWatchSession(
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
        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "test.\(UUID().uuidString)"
        )
        let owner = FolderWatchSessionCoordinator(makeFolderWatchController: {
            FolderWatchController(
                folderWatcher: TestFolderWatcher(),
                settingsStore: settingsStore,
                securityScope: TestSecurityScopeAccess(),
                systemNotifier: TestReaderSystemNotifier(),
                folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
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
