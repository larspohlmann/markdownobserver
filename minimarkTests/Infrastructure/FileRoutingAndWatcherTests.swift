//
//  FileRoutingAndWatcherTests.swift
//  minimarkTests
//

import CoreServices
import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FileRoutingAndWatcherTests {
    @Test func supportedMarkdownFilesFiltersAndNormalizes() {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let markdownURL = tempDirectory.appendingPathComponent("notes.MD")
        let markdownURL2 = tempDirectory.appendingPathComponent("design.markdown")
        let unsupportedURL = tempDirectory.appendingPathComponent("todo.txt")

        let output = ReaderFileRouting.supportedMarkdownFiles(from: [markdownURL, unsupportedURL, markdownURL2])

        #expect(output.count == 2)
        #expect(output.contains(ReaderFileRouting.normalizedFileURL(markdownURL)))
        #expect(output.contains(ReaderFileRouting.normalizedFileURL(markdownURL2)))
    }

    @Test func supportedMarkdownFilesAcceptsKnownExtensionsOnly() {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let supported = ["md", "markdown", "mdown"]
        let unsupported = ["txt", "rtf", ""]

        for ext in supported {
            let url = tempDirectory.appendingPathComponent("sample.\(ext)")
            #expect(ReaderFileRouting.isSupportedMarkdownFileURL(url))
        }

        for ext in unsupported {
            let filename = ext.isEmpty ? "sample" : "sample.\(ext)"
            let url = tempDirectory.appendingPathComponent(filename)
            #expect(!ReaderFileRouting.isSupportedMarkdownFileURL(url))
        }
    }

    @Test @MainActor func fileChangeWatcherDetectsContentChangeWithRestoredMetadata() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("tracked.md")
        try "aaaa".write(to: fileURL, atomically: false, encoding: .utf8)
        let originalModificationDate = try #require(
            FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
        )

        let watcher = makeFileChangeWatcher()
        var changeCount = 0

        try watcher.startWatching(fileURL: fileURL) {
            changeCount += 1
        }
        defer { watcher.stopWatching() }

        try "bbbb".write(to: fileURL, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: originalModificationDate], ofItemAtPath: fileURL.path)

        #expect(await waitUntil(timeout: .seconds(2)) { changeCount == 1 })
    }

    @Test @MainActor func fileChangeWatcherDetectsExternalDeletion() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("tracked.md")
        try "# Before".write(to: fileURL, atomically: false, encoding: .utf8)

        let watcher = makeFileChangeWatcher()
        var changeCount = 0

        try watcher.startWatching(fileURL: fileURL) {
            changeCount += 1
        }
        defer { watcher.stopWatching() }

        try FileManager.default.removeItem(at: fileURL)

        #expect(await waitUntil(timeout: .seconds(2)) { changeCount == 1 })
    }

    @Test @MainActor func fileChangeWatcherIgnoresModificationDateOnlyChangesWithoutContentChange() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("tracked.md")
        try "# Stable".write(to: fileURL, atomically: false, encoding: .utf8)

        let watcher = makeFileChangeWatcher()
        var changeCount = 0

        try watcher.startWatching(fileURL: fileURL) {
            changeCount += 1
        }
        defer { watcher.stopWatching() }

        let changedDate = Date(timeIntervalSinceNow: 5)
        try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: fileURL.path)
        try? await Task.sleep(for: .milliseconds(250))

        #expect(changeCount == 0)
    }

    @Test @MainActor func folderChangeWatcherReportsAddedAndModifiedFilesWithPreviousMarkdown() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let existingFileURL = directoryURL.appendingPathComponent("existing.md")
        let addedFileURL = directoryURL.appendingPathComponent("added.md")
        try "# Before".write(to: existingFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.didCompleteStartupForTesting
        })

        try "# After".write(to: existingFileURL, atomically: false, encoding: .utf8)
        try "# Added".write(to: addedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            let modifiedEvent = receivedEvents.first(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(existingFileURL) && $0.kind == .modified
            })
            let addedEvent = receivedEvents.first(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(addedFileURL) && $0.kind == .added
            })

            return modifiedEvent?.previousMarkdown == "# Before" && addedEvent != nil
        })
    }

    @Test @MainActor func folderChangeWatcherDetectsNestedSubfolderChangesWithoutPollingFallbackDelay() async throws {
        try await assertFolderChangeWatcherDetectsNestedSubfolderChange(
            subdirectoryComponents: ["nested"],
            fileName: "deep.md"
        )
    }

    @Test @MainActor func folderChangeWatcherDetectsHiddenSubfolderChangesWithoutPollingFallbackDelay() async throws {
        try await assertFolderChangeWatcherDetectsNestedSubfolderChange(
            subdirectoryComponents: [".github", "agents"],
            fileName: "instructions.md"
        )
    }

    @Test func folderChangeWatcherEnumeratesHiddenMarkdownFiles() throws {
        let directoryURL = try makeTemporaryDirectory()
        let hiddenSubdirectoryURL = directoryURL.appendingPathComponent(".notes", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenSubdirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let hiddenRootFileURL = directoryURL.appendingPathComponent(".draft.md")
        let hiddenNestedFileURL = hiddenSubdirectoryURL.appendingPathComponent("todo.md")
        let visibleFileURL = directoryURL.appendingPathComponent("visible.md")
        try "# Hidden root".write(to: hiddenRootFileURL, atomically: false, encoding: .utf8)
        try "# Hidden nested".write(to: hiddenNestedFileURL, atomically: false, encoding: .utf8)
        try "# Visible".write(to: visibleFileURL, atomically: false, encoding: .utf8)

        let watcher = FolderChangeWatcher()

        let selectedFolderOnlyFiles = try watcher.markdownFiles(in: directoryURL, includeSubfolders: false)
        let recursiveFiles = try watcher.markdownFiles(in: directoryURL, includeSubfolders: true)

        #expect(selectedFolderOnlyFiles == [
            ReaderFileRouting.normalizedFileURL(hiddenRootFileURL),
            ReaderFileRouting.normalizedFileURL(visibleFileURL)
        ].sorted(by: { $0.path < $1.path }))
        #expect(recursiveFiles == [
            ReaderFileRouting.normalizedFileURL(hiddenRootFileURL),
            ReaderFileRouting.normalizedFileURL(hiddenNestedFileURL),
            ReaderFileRouting.normalizedFileURL(visibleFileURL)
        ].sorted(by: { $0.path < $1.path }))
    }

    @Test func folderChangeWatcherExcludesConfiguredSubdirectoriesFromRecursiveEnumeration() throws {
        let directoryURL = try makeTemporaryDirectory()
        let includedSubdirectoryURL = directoryURL.appendingPathComponent("included", isDirectory: true)
        let excludedSubdirectoryURL = directoryURL.appendingPathComponent("excluded", isDirectory: true)
        try FileManager.default.createDirectory(at: includedSubdirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excludedSubdirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let includedFileURL = includedSubdirectoryURL.appendingPathComponent("included.md")
        let excludedFileURL = excludedSubdirectoryURL.appendingPathComponent("excluded.md")
        try "# Included".write(to: includedFileURL, atomically: false, encoding: .utf8)
        try "# Excluded".write(to: excludedFileURL, atomically: false, encoding: .utf8)

        let watcher = FolderChangeWatcher()
        let recursiveFiles = try watcher.markdownFiles(
            in: directoryURL,
            includeSubfolders: true,
            excludedSubdirectoryURLs: [excludedSubdirectoryURL]
        )

        #expect(recursiveFiles == [ReaderFileRouting.normalizedFileURL(includedFileURL)])
    }

    @Test func folderChangeWatcherLimitsRecursiveEnumerationToFiveLevels() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let depthFiveDirectoryURL = directoryURL
            .appendingPathComponent("l1", isDirectory: true)
            .appendingPathComponent("l2", isDirectory: true)
            .appendingPathComponent("l3", isDirectory: true)
            .appendingPathComponent("l4", isDirectory: true)
            .appendingPathComponent("l5", isDirectory: true)
        let depthSixDirectoryURL = depthFiveDirectoryURL.appendingPathComponent("l6", isDirectory: true)

        try FileManager.default.createDirectory(at: depthSixDirectoryURL, withIntermediateDirectories: true)

        let depthFiveFileURL = depthFiveDirectoryURL.appendingPathComponent("depth-five.md")
        let depthSixFileURL = depthSixDirectoryURL.appendingPathComponent("depth-six.md")
        try "# Depth five".write(to: depthFiveFileURL, atomically: false, encoding: .utf8)
        try "# Depth six".write(to: depthSixFileURL, atomically: false, encoding: .utf8)

        let watcher = FolderChangeWatcher()
        let recursiveFiles = try watcher.markdownFiles(in: directoryURL, includeSubfolders: true)

        #expect(recursiveFiles.contains(ReaderFileRouting.normalizedFileURL(depthFiveFileURL)))
        #expect(!recursiveFiles.contains(ReaderFileRouting.normalizedFileURL(depthSixFileURL)))
    }

    @Test func folderChangeWatcherStillAppliesDepthLimitWhenSubdirectoriesAreExplicitlyExcluded() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let includedBranchDepthSevenDirectoryURL = directoryURL
            .appendingPathComponent("included", isDirectory: true)
            .appendingPathComponent("l1", isDirectory: true)
            .appendingPathComponent("l2", isDirectory: true)
            .appendingPathComponent("l3", isDirectory: true)
            .appendingPathComponent("l4", isDirectory: true)
            .appendingPathComponent("l5", isDirectory: true)
            .appendingPathComponent("l6", isDirectory: true)
            .appendingPathComponent("l7", isDirectory: true)
        let excludedBranchDirectoryURL = directoryURL.appendingPathComponent("excluded", isDirectory: true)

        try FileManager.default.createDirectory(at: includedBranchDepthSevenDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excludedBranchDirectoryURL, withIntermediateDirectories: true)

        let deepIncludedFileURL = includedBranchDepthSevenDirectoryURL.appendingPathComponent("deep-include.md")
        try "# Deep include".write(to: deepIncludedFileURL, atomically: false, encoding: .utf8)

        let watcher = FolderChangeWatcher()
        let recursiveFiles = try watcher.markdownFiles(
            in: directoryURL,
            includeSubfolders: true,
            excludedSubdirectoryURLs: [excludedBranchDirectoryURL]
        )

        #expect(!recursiveFiles.contains(ReaderFileRouting.normalizedFileURL(deepIncludedFileURL)))
    }

    @Test @MainActor func folderChangeWatcherDoesNotEmitEventsFromExcludedSubdirectories() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let excludedSubdirectoryURL = directoryURL.appendingPathComponent("excluded", isDirectory: true)
        let includedSubdirectoryURL = directoryURL.appendingPathComponent("included", isDirectory: true)
        try FileManager.default.createDirectory(at: excludedSubdirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: includedSubdirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let excludedFileURL = excludedSubdirectoryURL.appendingPathComponent("ignored.md")
        let includedFileURL = includedSubdirectoryURL.appendingPathComponent("tracked.md")
        try "# Before".write(to: excludedFileURL, atomically: false, encoding: .utf8)
        try "# Before".write(to: includedFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(
            folderURL: directoryURL,
            includeSubfolders: true,
            excludedSubdirectoryURLs: [excludedSubdirectoryURL]
        ) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.didCompleteStartupForTesting
        })

        try "# After excluded".write(to: excludedFileURL, atomically: false, encoding: .utf8)
        try "# After included".write(to: includedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(includedFileURL) &&
                $0.kind == .modified
            })
        })

        #expect(!receivedEvents.contains(where: {
            $0.fileURL == ReaderFileRouting.normalizedFileURL(excludedFileURL)
        }))
    }

    @Test @MainActor func folderChangeWatcherDoesNotEmitInitialEventsForExistingNestedMarkdownFiles() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let nestedDirectoryURL = directoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let rootFileURL = directoryURL.appendingPathComponent("root.md")
        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("existing.md")
        try "# Root".write(to: rootFileURL, atomically: false, encoding: .utf8)
        try "# Nested".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        try? await Task.sleep(for: .milliseconds(250))

        #expect(receivedEvents.isEmpty)
    }

    @Test @MainActor func folderChangeWatcherIgnoresModificationDateOnlyChangesWithoutContentChange() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("tracked.md")
        try "# Stable".write(to: fileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        let changedDate = Date(timeIntervalSinceNow: 5)
        try FileManager.default.setAttributes([.modificationDate: changedDate], ofItemAtPath: fileURL.path)
        try? await Task.sleep(for: .milliseconds(250))

        #expect(receivedEvents.isEmpty)
    }

    @Test @MainActor func folderChangeWatcherSignalsStartupSnapshotFailureAndRecoversAfterFolderAppears() async throws {
        let baseDirectoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectoryURL) }

        let missingFolderURL = baseDirectoryURL.appendingPathComponent("missing", isDirectory: true)
        let recoveredFileURL = missingFolderURL.appendingPathComponent("recovered.md")

        let lock = NSLock()
        var failures: [FolderChangeWatcherFailure] = []
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        let watcher = makeFolderChangeWatcher(onFailure: { failure in
            lock.lock()
            failures.append(failure)
            lock.unlock()
        })

        try watcher.startWatching(folderURL: missingFolderURL, includeSubfolders: false) { events in
            lock.lock()
            receivedEvents.append(contentsOf: events)
            lock.unlock()
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return failures.contains(where: { $0.stage == .startupSnapshot })
        })

        lock.lock()
        let startupFailure = failures.first(where: { $0.stage == .startupSnapshot })
        lock.unlock()
        let startupFailureValue = try #require(startupFailure)
        #expect(!startupFailureValue.folderIdentifier.contains("/"))
        #expect(startupFailureValue.errorDescription.contains("domain:"))
        #expect(!startupFailureValue.errorDescription.contains(missingFolderURL.path))

        try FileManager.default.createDirectory(at: missingFolderURL, withIntermediateDirectories: true)
        try "# Recovered".write(to: recoveredFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(recoveredFileURL) &&
                $0.kind == .added
            })
        })
    }

    @Test @MainActor func folderChangeWatcherFailureCallbacksArriveOnMainThreadAndDeduplicateRepeatedVerificationErrors() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let trackedFileURL = directoryURL.appendingPathComponent("tracked.md")
        try "# Before".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        let lock = NSLock()
        var verificationFailures: [FolderChangeWatcherFailure] = []
        var callbackMainThreadFlags: [Bool] = []

        let watcher = makeFolderChangeWatcher(onFailure: { failure in
            lock.lock()
            callbackMainThreadFlags.append(Thread.isMainThread)
            if failure.stage == .verificationSnapshot {
                verificationFailures.append(failure)
            }
            lock.unlock()
        })

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { _ in }
        defer { watcher.stopWatching() }

        try? await Task.sleep(for: .milliseconds(200))
        try FileManager.default.removeItem(at: directoryURL)

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return !verificationFailures.isEmpty
        })

        try? await Task.sleep(for: .milliseconds(200))

        lock.lock()
        let firstFailureCount = verificationFailures.count
        let allCallbacksOnMainThread = callbackMainThreadFlags.allSatisfy { $0 }
        lock.unlock()

        #expect(firstFailureCount == 1)
        #expect(allCallbacksOnMainThread)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try "# Restored".write(to: trackedFileURL, atomically: false, encoding: .utf8)
        try? await Task.sleep(for: .milliseconds(200))

        try FileManager.default.removeItem(at: directoryURL)

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return verificationFailures.count == 2
        })
    }

    @Test @MainActor func folderChangeWatcherSignalsVerificationFailureAndRecoversAfterFolderRestored() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let trackedFileURL = directoryURL.appendingPathComponent("tracked.md")
        try "# Before".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        let lock = NSLock()
        var failures: [FolderChangeWatcherFailure] = []
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        let watcher = makeFolderChangeWatcher(onFailure: { failure in
            lock.lock()
            failures.append(failure)
            lock.unlock()
        })

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { events in
            lock.lock()
            receivedEvents.append(contentsOf: events)
            lock.unlock()
        }
        defer { watcher.stopWatching() }

        try? await Task.sleep(for: .milliseconds(200))
        try FileManager.default.removeItem(at: directoryURL)

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return failures.contains(where: { $0.stage == .verificationSnapshot })
        })

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let recoveredFileURL = directoryURL.appendingPathComponent("after-restore.md")
        try "# After restore".write(to: recoveredFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            lock.lock()
            defer { lock.unlock() }
            return receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(recoveredFileURL) &&
                $0.kind == .added
            })
        })
    }

    @Test @MainActor func recursiveFolderWatchDoesNotTriggerNestedFileWatcherWithoutRealFileChanges() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let nestedDirectoryURL = directoryURL
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("README.md")
        try "# Plan".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        let fileWatcher = makeFileChangeWatcher()
        let folderWatcher = makeFolderChangeWatcher()
        var fileChangeCount = 0
        var folderEvents: [ReaderFolderWatchChangeEvent] = []

        try fileWatcher.startWatching(fileURL: nestedFileURL) {
            fileChangeCount += 1
        }
        try folderWatcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            folderEvents.append(contentsOf: events)
        }
        defer {
            fileWatcher.stopWatching()
            folderWatcher.stopWatching()
        }

        try? await Task.sleep(for: .milliseconds(400))

        #expect(fileChangeCount == 0)
        #expect(folderEvents.isEmpty)
    }

    @Test @MainActor func recursiveFolderWatchFallsBackToPollingWhenTreeExceedsEventSourceLimit() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let deepFileURL = directoryURL
            .appendingPathComponent("level-0", isDirectory: true)
            .appendingPathComponent("level-1", isDirectory: true)
            .appendingPathComponent("level-2", isDirectory: true)
            .appendingPathComponent("tracked.md")
        try FileManager.default.createDirectory(
            at: deepFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try "# Before".write(to: deepFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher(
            fallbackPollingInterval: .seconds(5),
            maximumDirectoryEventSourceCount: 2
        )
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(!watcher.isUsingEventSourcesForTesting)
        #expect(watcher.activeDirectorySourceCountForTesting == 0)

        try "# After".write(to: deepFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(deepFileURL) &&
                $0.kind == .modified &&
                $0.previousMarkdown == "# Before"
            })
        })
    }

    @Test @MainActor func recursiveFolderWatchRetunesToNormalPollingAfterCrossingEventSourceLimit() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let nestedDirectoryURL = directoryURL.appendingPathComponent("level-0", isDirectory: true)
        let trackedFileURL = nestedDirectoryURL.appendingPathComponent("tracked.md")
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try "# Before".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher(
            fallbackPollingInterval: .seconds(5),
            maximumDirectoryEventSourceCount: 2
        )
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.didCompleteStartupForTesting
        })

        #expect(watcher.isUsingEventSourcesForTesting)
        #expect(watcher.isUsingRecursiveEventSourceSafetyPollingIntervalForTesting)

        let overLimitDirectoryURL = nestedDirectoryURL.appendingPathComponent("level-1", isDirectory: true)
        try FileManager.default.createDirectory(at: overLimitDirectoryURL, withIntermediateDirectories: true)

        #expect(await waitUntil(timeout: .seconds(2)) {
            !watcher.isUsingEventSourcesForTesting &&
            !watcher.isUsingFallbackPollingIntervalForTesting &&
            !watcher.isUsingRecursiveEventSourceSafetyPollingIntervalForTesting
        })

        try "# After".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(1)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(trackedFileURL) &&
                $0.kind == .modified &&
                $0.previousMarkdown == "# Before"
            })
        })
    }

    @Test @MainActor func recursiveEventSourceSafetyPollingBacksOffWhenIdleAndResetsAfterEvent() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let nestedDirectoryURL = directoryURL.appendingPathComponent("docs", isDirectory: true)
        let trackedFileURL = nestedDirectoryURL.appendingPathComponent("tracked.md")
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try "# Before".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        let baseSafetyInterval: DispatchTimeInterval = .milliseconds(60)
        let watcher = makeFolderChangeWatcher(
            fallbackPollingInterval: .seconds(5),
            recursiveEventSourceSafetyPollingInterval: baseSafetyInterval
        )
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.didCompleteStartupForTesting &&
            watcher.currentTimerIntervalForTesting == baseSafetyInterval
        })

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.currentTimerIntervalForTesting == .milliseconds(120)
        })

        try "# After".write(to: trackedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(2)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(trackedFileURL) &&
                $0.kind == .modified &&
                $0.previousMarkdown == "# Before"
            })
        })

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.currentTimerIntervalForTesting == baseSafetyInterval
        })
    }

    @Test @MainActor func profileFolderChangeWatcherStartupSnapshotForLargeCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PROFILE_STARTUP_SNAPSHOT"] == "1" else {
            return
        }

        let maximumProfileFileCount = 20_000
        let maximumProfileDepth = 8
        let resolvedFileCount = Int(environment["PROFILE_STARTUP_FILE_COUNT"] ?? "4000") ?? 4000
        let resolvedDepth = Int(environment["PROFILE_STARTUP_DEPTH"] ?? "3") ?? 3
        let fileCount = min(max(resolvedFileCount, 1), maximumProfileFileCount)
        let depth = min(max(resolvedDepth, 1), maximumProfileDepth)
        let includeSubfolders = environment["PROFILE_STARTUP_INCLUDE_SUBFOLDERS"] != "0"
        print(
            "PROFILE_STARTUP_CONFIG file_count=\(fileCount) depth=\(depth) include_subfolders=\(includeSubfolders)"
        )

        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        for index in 0..<fileCount {
            var parentURL = directoryURL
            for level in 0..<depth {
                let branch = (index + level) % 10
                parentURL = parentURL.appendingPathComponent("d\(level)-\(branch)", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
            let fileURL = parentURL.appendingPathComponent(String(format: "note-%05d.md", index))
            try "# Startup Profile \(index)".write(to: fileURL, atomically: false, encoding: .utf8)
        }

        let watcher = makeFolderChangeWatcher(fallbackPollingInterval: .seconds(5))
        let clock = ContinuousClock()
        let start = clock.now

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: includeSubfolders) { _ in }
        defer { watcher.stopWatching() }

        #expect(await waitUntil(timeout: .seconds(30)) {
            watcher.didCompleteStartupForTesting
        })

        let elapsed = start.duration(to: clock.now)
        let elapsedMilliseconds = Double(elapsed.components.seconds) * 1000.0 +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        let elapsedText = String(format: "%.2f", elapsedMilliseconds)
        print(
            "PROFILE_STARTUP_SNAPSHOT elapsed_ms=\(elapsedText) file_count=\(fileCount) depth=\(depth) include_subfolders=\(includeSubfolders)"
        )

        if let outputPath = environment["PROFILE_STARTUP_OUTPUT_PATH"],
           !outputPath.isEmpty {
            let outputURL = URL(fileURLWithPath: outputPath)
            let outputText = "elapsed_ms=\(elapsedText)\nfile_count=\(fileCount)\ndepth=\(depth)\ninclude_subfolders=\(includeSubfolders)\n"
            try outputText.write(to: outputURL, atomically: true, encoding: .utf8)
        }
    }

    @Test func readerFileActionServiceDeduplicatesApplicationsWithSameBundleIdentifier() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-file-action-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let markdownFileURL = temporaryDirectoryURL.appendingPathComponent("sample.md")
        try "# Sample".write(to: markdownFileURL, atomically: true, encoding: .utf8)

        let duplicateDebugAppURL = try makeTestApplicationBundle(
            at: temporaryDirectoryURL.appendingPathComponent("MarkdownObserver Debug.app"),
            bundleIdentifier: "org.markdownobserver.app",
            displayName: "MarkdownObserver"
        )
        let duplicateReleaseAppURL = try makeTestApplicationBundle(
            at: temporaryDirectoryURL.appendingPathComponent("MarkdownObserver Release.app"),
            bundleIdentifier: "org.markdownobserver.app",
            displayName: "MarkdownObserver"
        )
        let textEditAppURL = try makeTestApplicationBundle(
            at: temporaryDirectoryURL.appendingPathComponent("TextEdit.app"),
            bundleIdentifier: "com.apple.TextEdit",
            displayName: "TextEdit"
        )

        let workspace = TestWorkspace(
            applicationURLsToReturn: [duplicateReleaseAppURL, textEditAppURL, duplicateDebugAppURL]
        )
        let service = ReaderFileActionService(workspace: workspace)

        let applications = try service.registeredApplications(for: markdownFileURL)

        #expect(applications.count == 2)
        #expect(applications.map(\.id) == ["org.markdownobserver.app", "com.apple.TextEdit"])
        #expect(applications.filter { $0.bundleIdentifier == "org.markdownobserver.app" }.count == 1)
    }

    @Test func markdownAssociationServiceRegistersBundleBeforeUpdatingDefaults() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-association-service-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let bundleIdentifier = "org.markdownobserver.app.tests"
        let appURL = try makeTestApplicationBundle(
            at: temporaryDirectoryURL.appendingPathComponent("MarkdownObserver.app"),
            bundleIdentifier: bundleIdentifier,
            displayName: "MarkdownObserver"
        )
        let bundle = try #require(Bundle(url: appURL))
        let launchServices = TestLaunchServices()
        let service = ReaderDefaultMarkdownAssociationService(
            launchServices: launchServices,
            typeResolver: TestMarkdownContentTypeResolver(identifiers: ["net.daringfireball.markdown"]),
            appBundle: bundle
        )

        let result = try service.setCurrentAppAsDefaultForMarkdown()

        #expect(result.bundleIdentifier == bundleIdentifier)
        #expect(result.updatedContentTypes == ["net.daringfireball.markdown"])
        #expect(launchServices.recordedOperations == [
            .register(appURL.path),
            .setDefault("net.daringfireball.markdown", bundleIdentifier),
            .copyDefault("net.daringfireball.markdown")
        ])
    }

    @Test func markdownAssociationServiceReportsBundleRegistrationFailure() throws {
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-association-service-registration-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let appURL = try makeTestApplicationBundle(
            at: temporaryDirectoryURL.appendingPathComponent("MarkdownObserver.app"),
            bundleIdentifier: "org.markdownobserver.app.tests",
            displayName: "MarkdownObserver"
        )
        let bundle = try #require(Bundle(url: appURL))
        let launchServices = TestLaunchServices(registerStatus: -10814)
        let service = ReaderDefaultMarkdownAssociationService(
            launchServices: launchServices,
            typeResolver: TestMarkdownContentTypeResolver(identifiers: ["net.daringfireball.markdown"]),
            appBundle: bundle
        )

        #expect(throws: MarkdownAssociationError.bundleRegistrationFailed(status: -10814)) {
            try service.setCurrentAppAsDefaultForMarkdown()
        }
        #expect(launchServices.recordedOperations == [.register(appURL.path)])
    }
}

private extension FileRoutingAndWatcherTests {
    nonisolated static let defaultPollingInterval: DispatchTimeInterval = .milliseconds(50)
    nonisolated static let defaultFallbackPollingInterval: DispatchTimeInterval = .milliseconds(80)
    nonisolated static let defaultVerificationDelay: DispatchTimeInterval = .milliseconds(20)

    func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func makeFileChangeWatcher() -> FileChangeWatcher {
        FileChangeWatcher(
            pollingInterval: Self.defaultPollingInterval,
            fallbackPollingInterval: Self.defaultFallbackPollingInterval,
            verificationDelay: Self.defaultVerificationDelay
        )
    }

    func makeFolderChangeWatcher(
        fallbackPollingInterval: DispatchTimeInterval = defaultFallbackPollingInterval,
        recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval? = nil,
        maximumDirectoryEventSourceCount: Int? = nil,
        onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)? = nil
    ) -> FolderChangeWatcher {
        guard let maximumDirectoryEventSourceCount else {
            return FolderChangeWatcher(
                pollingInterval: Self.defaultPollingInterval,
                fallbackPollingInterval: fallbackPollingInterval,
                recursiveEventSourceSafetyPollingInterval: recursiveEventSourceSafetyPollingInterval ?? .seconds(
                    ReaderFolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
                ),
                verificationDelay: Self.defaultVerificationDelay,
                onFailure: onFailure
            )
        }

        return FolderChangeWatcher(
            pollingInterval: Self.defaultPollingInterval,
            fallbackPollingInterval: fallbackPollingInterval,
            recursiveEventSourceSafetyPollingInterval: recursiveEventSourceSafetyPollingInterval ?? .seconds(
                ReaderFolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
            ),
            verificationDelay: Self.defaultVerificationDelay,
            maximumDirectoryEventSourceCount: maximumDirectoryEventSourceCount,
            onFailure: onFailure
        )
    }

    @MainActor
    func assertFolderChangeWatcherDetectsNestedSubfolderChange(
        subdirectoryComponents: [String],
        fileName: String
    ) async throws {
        let directoryURL = try makeTemporaryDirectory()
        let nestedDirectoryURL = subdirectoryComponents.reduce(directoryURL) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let nestedFileURL = nestedDirectoryURL.appendingPathComponent(fileName)
        try "# Before".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher(fallbackPollingInterval: .seconds(5))
        var receivedEvents: [ReaderFolderWatchChangeEvent] = []

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: true) { events in
            receivedEvents.append(contentsOf: events)
        }
        defer { watcher.stopWatching() }

        let expectedDirectorySourceCount = subdirectoryComponents.count + 1
        let watcherReady = await waitUntil(timeout: .seconds(3)) {
            watcher.activeDirectorySourceCountForTesting >= expectedDirectorySourceCount
        }
        #expect(watcherReady)

        #expect(await waitUntil(timeout: .seconds(2)) {
            watcher.didCompleteStartupForTesting
        })

        try "# After".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(6)) {
            receivedEvents.contains(where: {
                $0.fileURL == ReaderFileRouting.normalizedFileURL(nestedFileURL) &&
                $0.kind == .modified &&
                $0.previousMarkdown == "# Before"
            })
        })
    }
}

private struct TestMarkdownContentTypeResolver: MarkdownContentTypeResolving {
    let identifiers: [String]

    func markdownContentTypeIdentifiers() -> [String] {
        identifiers
    }
}

private final class TestLaunchServices: LaunchServicesControlling {
    enum Operation: Equatable {
        case register(String)
        case setDefault(String, String)
        case copyDefault(String)
    }

    private let registerStatus: OSStatus
    private var handlersByContentType: [String: String] = [:]

    private(set) var recordedOperations: [Operation] = []

    init(registerStatus: OSStatus = noErr) {
        self.registerStatus = registerStatus
    }

    func registerApplication(at url: URL) -> OSStatus {
        recordedOperations.append(.register(url.path))
        return registerStatus
    }

    func setDefaultRoleHandler(contentType: String, role: LSRolesMask, handlerBundleID: String) -> OSStatus {
        recordedOperations.append(.setDefault(contentType, handlerBundleID))
        handlersByContentType[contentType] = handlerBundleID
        return noErr
    }

    func copyDefaultRoleHandler(contentType: String, role: LSRolesMask) -> String? {
        recordedOperations.append(.copyDefault(contentType))
        return handlersByContentType[contentType]
    }
}
