//
//  FolderEventSourceTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderEventSourceTests {

    // MARK: - FSEvents integration

    @Test @MainActor func fsEventStreamDetectsFileCreationInRecursiveWatch() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let docsURL = directoryURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        let newFileURL = docsURL.appendingPathComponent("new-file.md")
        try "# New File".write(to: newFileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(newFileURL) &&
                $0.kind == .added
            })
        })
    }

    @Test @MainActor func fsEventStreamDetectsFileModificationInRecursiveWatch() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let notesURL = directoryURL.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let existingFileURL = notesURL.appendingPathComponent("existing.md")
        try "# Before".write(to: existingFileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        try "# After".write(to: existingFileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(existingFileURL) &&
                $0.kind == .modified &&
                $0.previousMarkdown == "# Before"
            })
        })
    }

    @Test @MainActor func fsEventStreamRespectsExcludedSubdirectories() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let excludedURL = directoryURL.appendingPathComponent("excluded", isDirectory: true)
        let includedURL = directoryURL.appendingPathComponent("included", isDirectory: true)
        try FileManager.default.createDirectory(at: excludedURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includedURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let excludedFileURL = excludedURL.appendingPathComponent("ignored.md")
        let includedFileURL = includedURL.appendingPathComponent("tracked.md")
        try "# Before".write(to: excludedFileURL, atomically: true, encoding: .utf8)
        try "# Before".write(to: includedFileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(
            folderURL: directoryURL,
            includeSubfolders: true,
            excludedSubdirectoryURLs: [excludedURL]
        ) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        try "# After excluded".write(to: excludedFileURL, atomically: true, encoding: .utf8)
        try "# After included".write(to: includedFileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(includedFileURL) &&
                $0.kind == .modified
            })
        })

        #expect(!receivedEvents.contains(where: {
            $0.fileURL == ReaderFileRouting.normalizedFileURL(excludedFileURL)
        }))
    }

    // MARK: - Factory selection

    @Test func factorySelectsFSEventsForRecursiveAndDispatchSourceForFlat() {
        let recursiveSource = FolderEventSourceFactory.makeEventSource(includeSubfolders: true)
        #expect(recursiveSource is FSEventStreamFolderEventSource)

        let flatSource = FolderEventSourceFactory.makeEventSource(includeSubfolders: false)
        #expect(flatSource is DispatchSourceFolderEventSource)
    }
}

// MARK: - Helpers

private extension FolderEventSourceTests {
    nonisolated static let defaultVerificationDelay: DispatchTimeInterval = .milliseconds(20)

    func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func makeFSEventsWatcher() -> FolderChangeWatcher {
        FolderChangeWatcher(
            verificationDelay: Self.defaultVerificationDelay,
            makeEventSource: { _ in
                FSEventStreamFolderEventSource(
                    latency: 0.1,
                    safetyPollingInterval: .seconds(30)
                )
            }
        )
    }
}
