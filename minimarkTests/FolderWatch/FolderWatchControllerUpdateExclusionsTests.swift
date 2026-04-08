import Foundation
import Testing
@testable import minimark

@Suite("FolderWatchController Update Exclusions")
@MainActor
struct FolderWatchControllerUpdateExclusionsTests {

    @Test func updateExclusionsRestartsWatcherWithNewPaths() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder", isDirectory: true)
        let initialOptions = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: ["/tmp/test-folder/excluded"]
        )
        let updatedExclusions = ["/tmp/test-folder/excluded", "/tmp/test-folder/another"]

        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.update-excl.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(folderURL: folderURL, options: initialOptions, performInitialAutoOpen: false)
        let firstSession = controller.activeFolderWatchSession
        #expect(firstSession != nil)
        #expect(firstSession?.options.excludedSubdirectoryPaths == ["/tmp/test-folder/excluded"])
        #expect(watcher.startCallCount == 1)
        #expect(watcher.stopCallCount == 1)

        try controller.updateExcludedSubdirectories(updatedExclusions)

        let secondSession = controller.activeFolderWatchSession
        #expect(secondSession != nil)
        #expect(secondSession?.options.excludedSubdirectoryPaths == updatedExclusions)
        #expect(secondSession?.folderURL == firstSession?.folderURL)
        #expect(secondSession?.options.openMode == firstSession?.options.openMode)
        #expect(secondSession?.options.scope == firstSession?.options.scope)
        #expect(watcher.startCallCount == 2)
        #expect(watcher.stopCallCount == 2)
    }

    @Test func updateExclusionsThrowsWhenNotWatching() {
        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.update-excl-err.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        #expect(throws: FolderWatchUpdateError.self) {
            try controller.updateExcludedSubdirectories(["/some/path"])
        }
    }
}
