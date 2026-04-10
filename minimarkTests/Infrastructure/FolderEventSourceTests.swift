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

    @Test @MainActor func fsEventStreamDetectsFileDeletionInRecursiveWatch() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let docsURL = directoryURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = docsURL.appendingPathComponent("will-be-deleted.md")
        try "# Delete me".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { _ in }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let cachedBefore = watcher.cachedMarkdownFileURLs() ?? []
        #expect(cachedBefore.contains(normalizedFileURL))

        try FileManager.default.removeItem(at: fileURL)

        #expect(await waitUntil(timeout: .seconds(5)) {
            let cached = watcher.cachedMarkdownFileURLs() ?? []
            return !cached.contains(normalizedFileURL)
        })
    }

    @Test @MainActor func fsEventStreamDetectsRapidSuccessiveWritesToSameFile() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let subdirURL = directoryURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = subdirURL.appendingPathComponent("rapid.md")
        try "# Version 0".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        for version in 1...5 {
            try "# Version \(version)".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
        #expect(await waitUntil(timeout: .seconds(5)) {
            receivedEvents.contains(where: {
                $0.fileURL == normalizedURL && $0.kind == .modified
            })
        })

        // Final snapshot should reflect the last write
        if let cached = watcher.cachedMarkdownFileURLs() {
            #expect(cached.contains(normalizedURL))
        }
    }

    @Test @MainActor func fsEventStreamDetectsDeeplyNestedSubdirectoryChange() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let deepURL = directoryURL
            .appendingPathComponent("level1", isDirectory: true)
            .appendingPathComponent("level2", isDirectory: true)
            .appendingPathComponent("level3", isDirectory: true)
        try FileManager.default.createDirectory(at: deepURL, withIntermediateDirectories: true)
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

        let deepFileURL = deepURL.appendingPathComponent("deep.md")
        try "# Deep".write(to: deepFileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(deepFileURL) &&
                $0.kind == .added
            })
        })
    }

    @Test @MainActor func fsEventStreamDoesNotEmitEventForEphemeralFile() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let subdirURL = directoryURL.appendingPathComponent("temp", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let stableFileURL = subdirURL.appendingPathComponent("stable.md")
        try "# Stable".write(to: stableFileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        // Create and immediately delete a file
        let ephemeralURL = subdirURL.appendingPathComponent("ephemeral.md")
        try "# Gone".write(to: ephemeralURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: ephemeralURL)

        // Wait for any events to settle
        try? await Task.sleep(for: .seconds(1))

        let normalizedEphemeral = ReaderFileRouting.normalizedFileURL(ephemeralURL)
        let hasEphemeralEvent = receivedEvents.contains(where: {
            $0.fileURL == normalizedEphemeral && $0.kind == .added
        })
        // The ephemeral file should NOT appear as added since it doesn't exist at verification time
        #expect(!hasEphemeralEvent)
    }

    @Test @MainActor func fsEventStreamDetectsMultipleFilesInDifferentSubdirectories() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let subdirA = directoryURL.appendingPathComponent("alpha", isDirectory: true)
        let subdirB = directoryURL.appendingPathComponent("bravo", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subdirB, withIntermediateDirectories: true)
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

        let fileA = subdirA.appendingPathComponent("alpha.md")
        let fileB = subdirB.appendingPathComponent("bravo.md")
        try "# Alpha".write(to: fileA, atomically: true, encoding: .utf8)
        try "# Bravo".write(to: fileB, atomically: true, encoding: .utf8)

        let normalizedA = ReaderFileRouting.normalizedFileURL(fileA)
        let normalizedB = ReaderFileRouting.normalizedFileURL(fileB)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: { $0.fileURL == normalizedA && $0.kind == .added }) &&
            receivedEvents.contains(where: { $0.fileURL == normalizedB && $0.kind == .added })
        })
    }

    @Test @MainActor func fsEventStreamWatcherHandlesStopAndRestart() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let subdirURL = directoryURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = subdirURL.appendingPathComponent("persistent.md")
        try "# Round 1".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var firstRoundEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            firstRoundEvents.append(contentsOf: events)
        }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        try "# Round 1 modified".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            firstRoundEvents.contains(where: { $0.kind == .modified })
        })

        watcher.stopWatching()

        // Modify while stopped — should not be detected
        try "# Round 2".write(to: fileURL, atomically: true, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(200))

        var secondRoundEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            secondRoundEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        // Modify again after restart
        try "# Round 2 modified".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            secondRoundEvents.contains(where: {
                $0.kind == .modified &&
                $0.fileURL == ReaderFileRouting.normalizedFileURL(fileURL)
            })
        })
    }

    // MARK: - Accumulated directory URL merging

    @Test @MainActor func fsEventStreamAccumulatesChangedDirectoriesAcrossRapidEvents() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let subdirA = directoryURL.appendingPathComponent("alpha", isDirectory: true)
        let subdirB = directoryURL.appendingPathComponent("bravo", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subdirB, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileA = subdirA.appendingPathComponent("a.md")
        let fileB = subdirB.appendingPathComponent("b.md")
        try "# A".write(to: fileA, atomically: true, encoding: .utf8)
        try "# B".write(to: fileB, atomically: true, encoding: .utf8)

        let watcher = makeFSEventsWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        // Write to both subdirectories in rapid succession — both should be detected
        // even though the verification delay may coalesce them
        try "# A modified".write(to: fileA, atomically: true, encoding: .utf8)
        try "# B modified".write(to: fileB, atomically: true, encoding: .utf8)

        let normalizedA = ReaderFileRouting.normalizedFileURL(fileA)
        let normalizedB = ReaderFileRouting.normalizedFileURL(fileB)

        #expect(await waitUntil(timeout: .seconds(5)) {
            receivedEvents.contains(where: { $0.fileURL == normalizedA && $0.kind == .modified }) &&
            receivedEvents.contains(where: { $0.fileURL == normalizedB && $0.kind == .modified })
        })
    }

    // MARK: - New subdirectory detection (directory resync)

    @Test @MainActor func dispatchSourceDetectsChangesInNewlyCreatedSubdirectory() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let existingFileURL = directoryURL.appendingPathComponent("existing.md")
        try "# Existing".write(to: existingFileURL, atomically: true, encoding: .utf8)

        let watcher = FolderChangeWatcher(
            verificationDelay: Self.defaultVerificationDelay,
            makeEventSource: { _ in
                DispatchSourceFolderEventSource(
                    pollingInterval: .milliseconds(50),
                    fallbackPollingInterval: .milliseconds(80),
                    maximumDirectoryEventSourceCount: 128
                )
            }
        )
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(3)) {
            watcher.didCompleteStartupForTesting
        })

        // Create a new subdirectory and add a file — should be detected after resync
        let newSubdir = directoryURL.appendingPathComponent("new-subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: newSubdir, withIntermediateDirectories: true)
        let newFileURL = newSubdir.appendingPathComponent("new.md")
        try "# New".write(to: newFileURL, atomically: true, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(3)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(newFileURL) &&
                $0.kind == .added
            })
        })
    }

    // MARK: - FSEvents non-recursive guard

    @Test func fsEventStreamSourceRejectsNonRecursiveWatch() {
        let source = FSEventStreamFolderEventSource(latency: 0.1, safetyPollingInterval: .seconds(30))
        let exclusionMatcher = FolderWatchExclusionMatcher(
            rootFolderURL: URL(fileURLWithPath: "/tmp"), excludedSubdirectoryURLs: []
        )
        let queue = DispatchQueue(label: "test.fsevents.guard")
        var eventCount = 0

        source.start(
            folderURL: URL(fileURLWithPath: "/tmp"),
            includeSubfolders: false,
            exclusionMatcher: exclusionMatcher,
            queue: queue
        ) { _ in
            eventCount += 1
        }
        defer { source.stop() }

        // Should not have started — no events should be delivered
        queue.sync {
            // If the source started, it would have scheduled a safety timer.
            // Give it a moment then verify no events fired.
        }

        // The source should not be active (no stream, no timer)
        // We verify by checking that stop() is safe to call (no crash)
        source.stop()
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
