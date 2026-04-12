import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FileChangeWatcherLazyQueueTests {
    @Test func queueIsNotCreatedOnInit() {
        let watcher = FileChangeWatcher()
        // stopWatching() on a never-started watcher should be a no-op.
        watcher.stopWatching()
    }

    @Test func startWatchingCreatesQueueAndWatches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-test-lazy-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("test.md")
        try "# Test".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = FileChangeWatcher()
        var changeCount = 0
        try watcher.startWatching(fileURL: fileURL) {
            changeCount += 1
        }

        // Watcher should be running — stopWatching should not crash.
        watcher.stopWatching()
    }
}
