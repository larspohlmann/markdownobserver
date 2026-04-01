//
//  FolderChangeWatcherScanProgressTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderChangeWatcherScanProgressTests {
    private static let defaultPollingInterval: DispatchTimeInterval = .milliseconds(50)
    private static let defaultFallbackPollingInterval: DispatchTimeInterval = .milliseconds(100)
    private static let defaultVerificationDelay: DispatchTimeInterval = .milliseconds(25)

    @Test @MainActor func scanProgressStreamEmitsProgressAndCompletes() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL1 = directoryURL.appendingPathComponent("a.md")
        let fileURL2 = directoryURL.appendingPathComponent("b.md")
        try "# A".write(to: fileURL1, atomically: false, encoding: .utf8)
        try "# B".write(to: fileURL2, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { _ in }
        defer { watcher.stopWatching() }

        var progressUpdates: [FolderChangeWatcher.ScanProgress] = []
        for await progress in watcher.scanProgressStream {
            progressUpdates.append(progress)
        }

        #expect(!progressUpdates.isEmpty)

        let final = try #require(progressUpdates.last)
        #expect(final.total == 2)
        #expect(final.completed == 2)
        #expect(final.isFinished)
    }

    @Test @MainActor func scanProgressStreamEmitsZeroTotalForEmptyFolder() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let watcher = makeFolderChangeWatcher()

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { _ in }
        defer { watcher.stopWatching() }

        var progressUpdates: [FolderChangeWatcher.ScanProgress] = []
        for await progress in watcher.scanProgressStream {
            progressUpdates.append(progress)
        }

        let final = try #require(progressUpdates.last)
        #expect(final.total == 0)
        #expect(final.completed == 0)
        #expect(final.isFinished)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeFolderChangeWatcher() -> FolderChangeWatcher {
        FolderChangeWatcher(
            pollingInterval: Self.defaultPollingInterval,
            fallbackPollingInterval: Self.defaultFallbackPollingInterval,
            verificationDelay: Self.defaultVerificationDelay
        )
    }
}
