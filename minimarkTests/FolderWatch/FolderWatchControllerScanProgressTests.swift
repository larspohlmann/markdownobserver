//
//  FolderWatchControllerScanProgressTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderWatchControllerScanProgressTests {
    @Test @MainActor func controllerPublishesScanProgressFromWatcherStream() async throws {
        let folderWatcher = TestFolderWatcher()
        let (stream, continuation) = AsyncStream.makeStream(of: FolderChangeWatcher.ScanProgress.self)
        folderWatcher.scanProgressStreamToReturn = stream

        let controller = makeController(folderWatcher: folderWatcher)
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder")

        try controller.startWatching(
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            performInitialAutoOpen: false
        )

        #expect(controller.contentScanProgress == nil)

        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 1, total: 3))

        #expect(await waitUntil(timeout: .seconds(5)) { controller.contentScanProgress?.completed == 1 })
        #expect(controller.contentScanProgress?.total == 3)

        // Keep the stream open while asserting the finished value. The controller
        // clears `contentScanProgress` a short time after the stream finishes, so
        // finishing first makes the finished value transient and the wait flaky.
        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 3, total: 3))

        #expect(await waitUntil(timeout: .seconds(5)) { controller.contentScanProgress?.isFinished == true })

        continuation.finish()
        controller.stopWatching()
    }

    @Test @MainActor func controllerClearsScanProgressOnStop() async throws {
        let folderWatcher = TestFolderWatcher()
        let (stream, continuation) = AsyncStream.makeStream(of: FolderChangeWatcher.ScanProgress.self)
        folderWatcher.scanProgressStreamToReturn = stream

        let controller = makeController(folderWatcher: folderWatcher)
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder")

        try controller.startWatching(
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            performInitialAutoOpen: false
        )

        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 1, total: 3))
        #expect(await waitUntil { controller.contentScanProgress != nil })

        controller.stopWatching()
        #expect(controller.contentScanProgress == nil)
    }

    @MainActor private func makeController(folderWatcher: TestFolderWatcher) -> FolderWatchController {
        let settingsStore = SettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.scan-progress-tests.\(UUID().uuidString)"
        )
        return FolderWatchController(
            folderWatcher: folderWatcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestSystemNotifier(),
            folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
        )
    }
}
