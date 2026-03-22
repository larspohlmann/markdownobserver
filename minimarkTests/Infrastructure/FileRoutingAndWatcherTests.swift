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

        #expect(watcher.isUsingEventSourcesForTesting)
        #expect(watcher.isUsingFallbackPollingIntervalForTesting)

        let overLimitDirectoryURL = nestedDirectoryURL.appendingPathComponent("level-1", isDirectory: true)
        try FileManager.default.createDirectory(at: overLimitDirectoryURL, withIntermediateDirectories: true)

        #expect(await waitUntil(timeout: .seconds(2)) {
            !watcher.isUsingEventSourcesForTesting && !watcher.isUsingFallbackPollingIntervalForTesting
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
        maximumDirectoryEventSourceCount: Int? = nil
    ) -> FolderChangeWatcher {
        guard let maximumDirectoryEventSourceCount else {
            return FolderChangeWatcher(
                pollingInterval: Self.defaultPollingInterval,
                fallbackPollingInterval: fallbackPollingInterval,
                verificationDelay: Self.defaultVerificationDelay
            )
        }

        return FolderChangeWatcher(
            pollingInterval: Self.defaultPollingInterval,
            fallbackPollingInterval: fallbackPollingInterval,
            verificationDelay: Self.defaultVerificationDelay,
            maximumDirectoryEventSourceCount: maximumDirectoryEventSourceCount
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

        try "# After".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        #expect(await waitUntil(timeout: .seconds(4)) {
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
