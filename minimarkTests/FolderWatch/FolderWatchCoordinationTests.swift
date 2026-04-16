//
//  FolderWatchCoordinationTests.swift
//  minimarkTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderWatchCoordinationTests {
    @Test func folderWatchAutoOpenPlannerCapsInitialBatchAndSkipsCurrentDocument() {
        let planner = ReaderFolderWatchAutoOpenPlanner()
        let folderURL = URL(fileURLWithPath: "/tmp/watched")
        let currentDocumentURL = folderURL.appendingPathComponent("keep-open.md")
        let session = ReaderFolderWatchSession(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            startedAt: Date(timeIntervalSince1970: 321)
        )
        let events = [
            ReaderFolderWatchChangeEvent(fileURL: currentDocumentURL, kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: folderURL.appendingPathComponent("ignored.txt"), kind: .added)
        ] + (0...ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount).map { index in
            ReaderFolderWatchChangeEvent(
                fileURL: folderURL.appendingPathComponent(String(format: "note-%02d.md", index)),
                kind: .added
            )
        }

        let plan = planner.initialPlan(
            for: events,
            activeSession: session,
            currentDocumentFileURL: currentDocumentURL
        )

        #expect(plan.autoOpenEvents.count == ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
        #expect(!plan.autoOpenEvents.map(\.fileURL).contains(currentDocumentURL))
        #expect(!plan.autoOpenEvents.map(\.fileURL).contains(folderURL.appendingPathComponent("ignored.txt")))
        #expect(plan.warning?.folderURL == folderURL)
        #expect(plan.warning?.omittedFileURLs == [folderURL.appendingPathComponent("note-12.md")])
    }

    @Test @MainActor func burstOpenPlanningNormalizesDeduplicatesAndSorts() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let urls: [URL] = [
            URL(fileURLWithPath: "/tmp/zeta.md"),
            URL(fileURLWithPath: "/tmp/alpha.md"),
            URL(fileURLWithPath: "/tmp/alpha.md"),
            URL(fileURLWithPath: "/tmp/notes.markdown")
        ]

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: urls,
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))

        #expect(plan.assignments.map(\.fileURL.path) == [
            "/tmp/alpha.md",
            "/tmp/notes.markdown",
            "/tmp/zeta.md"
        ])
    }

    @Test @MainActor func folderWatchControllerLoadsIncludeSubfoldersInitialBatchWithoutBlockingStart() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-\(UUID().uuidString)", isDirectory: true)
        let initialFileURL = folderURL.appendingPathComponent("initial.md")
        let watcher = TestFolderWatcher()
        watcher.markdownFilesDelay = 0.35
        watcher.markdownFilesToReturn = [initialFileURL]
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.async-start.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
        let delegate = TestFolderWatchControllerDelegate()
        controller.delegate = delegate

        let startedAt = Date()
        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(elapsed < 0.2)
        #expect(delegate.handledEvents.isEmpty)

        #expect(await waitUntil(timeout: .seconds(2)) {
            delegate.handledEvents.map(\.fileURL) == [ReaderFileRouting.normalizedFileURL(initialFileURL)]
        })
    }

    @Test @MainActor func folderWatchControllerDiscardsStaleIncludeSubfoldersInitialBatchAfterRestart() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-\(UUID().uuidString)", isDirectory: true)
        let staleFileURL = folderURL.appendingPathComponent("stale.md")
        let watcher = TestFolderWatcher()
        watcher.markdownFilesDelay = 0.25
        watcher.markdownFilesToReturn = [staleFileURL]
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.stale-initial.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
        let delegate = TestFolderWatchControllerDelegate()
        controller.delegate = delegate

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders
            )
        )

        try? await Task.sleep(for: .milliseconds(500))

        #expect(delegate.handledEvents.isEmpty)
    }

    @Test @MainActor func folderWatchControllerPublishesInitialScanProgressStateForIncludeSubfolders() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-\(UUID().uuidString)", isDirectory: true)
        let initialFileURL = folderURL.appendingPathComponent("initial.md")
        let watcher = TestFolderWatcher()
        watcher.markdownFilesDelay = 0.3
        watcher.markdownFilesToReturn = [initialFileURL]
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.progress.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )

        #expect(controller.isInitialMarkdownScanInProgress)

        #expect(await waitUntil(timeout: .seconds(2)) {
            !controller.isInitialMarkdownScanInProgress
        })
    }

    @Test @MainActor func folderWatchControllerClearsInitialScanProgressWhenStopped() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-\(UUID().uuidString)", isDirectory: true)
        let watcher = TestFolderWatcher()
        watcher.markdownFilesDelay = 0.8
        watcher.markdownFilesToReturn = [folderURL.appendingPathComponent("initial.md")]
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.progress-stop.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )
        #expect(controller.isInitialMarkdownScanInProgress)

        controller.stopWatching()

        #expect(!controller.isInitialMarkdownScanInProgress)
    }

    @Test @MainActor func folderWatchControllerFlagsInitialScanFailureForIncludeSubfolders() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-failure-\(UUID().uuidString)", isDirectory: true)
        let watcher = TestFolderWatcher()
        watcher.markdownFilesError = NSError(domain: "FolderWatchCoordinationTests", code: 77)
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.scan-failure.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
        let delegate = TestFolderWatchControllerDelegate()
        controller.delegate = delegate

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )

        #expect(controller.isInitialMarkdownScanInProgress)

        #expect(await waitUntil(timeout: .seconds(2)) {
            controller.didInitialMarkdownScanFail && !controller.isInitialMarkdownScanInProgress
        })
        #expect(delegate.handledEvents.isEmpty)
    }

    @Test @MainActor func folderWatchControllerIgnoresStaleInitialScanCompletionAfterRestart() async throws {
        let firstFolderURL = URL(fileURLWithPath: "/tmp/watched-first-\(UUID().uuidString)", isDirectory: true)
        let secondFolderURL = URL(fileURLWithPath: "/tmp/watched-second-\(UUID().uuidString)", isDirectory: true)
        let watcher = TestFolderWatcher()
        watcher.markdownFilesDelay = 0.4
        watcher.markdownFilesToReturn = [firstFolderURL.appendingPathComponent("initial.md")]
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.progress-restart.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(
            folderURL: firstFolderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )
        #expect(controller.isInitialMarkdownScanInProgress)

        try? await Task.sleep(for: .milliseconds(100))

        try controller.startWatching(
            folderURL: secondFolderURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )

        try? await Task.sleep(for: .milliseconds(350))
        #expect(controller.isInitialMarkdownScanInProgress)

        #expect(await waitUntil(timeout: .seconds(2)) {
            !controller.isInitialMarkdownScanInProgress
        })
    }

    @Test @MainActor func folderWatchOpenCoordinatorDeduplicatesAndBuildsLatestBatch() {
        let coordinator = ReaderFolderWatchOpenCoordinator()
        let watchSession = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: Date(timeIntervalSince1970: 456)
        )
        let fileURL = URL(fileURLWithPath: "/tmp/queued.md")

        coordinator.enqueue(
            ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: "# Before"
            ),
            folderWatchSession: watchSession,
            origin: .folderWatchAutoOpen,
            onFlushRequested: {}
        )
        coordinator.enqueue(
            ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: "# Latest Before"
            ),
            folderWatchSession: watchSession,
            origin: .folderWatchInitialBatchAutoOpen,
            onFlushRequested: {}
        )

        let batch = coordinator.consumeBatchIfPossible(canFlushImmediately: true, onFlushRequested: {})

        #expect(batch?.fileURLs == [ReaderFileRouting.normalizedFileURL(fileURL)])
        #expect(batch?.initialDiffBaselineMarkdownByURL[ReaderFileRouting.normalizedFileURL(fileURL)] == "# Latest Before")
        #expect(batch?.folderWatchSession == watchSession)
        #expect(batch?.openOrigin == .folderWatchInitialBatchAutoOpen)
        #expect(!coordinator.hasPendingEvents)
    }

    @Test @MainActor func folderWatchOpenCoordinatorPreservesAddedSemanticsWhenModifiedArrivesBeforeFlush() {
        let coordinator = ReaderFolderWatchOpenCoordinator()
        let watchSession = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: Date(timeIntervalSince1970: 456)
        )
        let fileURL = URL(fileURLWithPath: "/tmp/newly-created.md")

        coordinator.enqueue(
            ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .added
            ),
            folderWatchSession: watchSession,
            origin: .folderWatchAutoOpen,
            onFlushRequested: {}
        )
        coordinator.enqueue(
            ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: ""
            ),
            folderWatchSession: watchSession,
            origin: .folderWatchAutoOpen,
            onFlushRequested: {}
        )

        let batch = coordinator.consumeBatchIfPossible(canFlushImmediately: true, onFlushRequested: {})

        #expect(batch?.fileURLs == [ReaderFileRouting.normalizedFileURL(fileURL)])
        #expect(batch?.initialDiffBaselineMarkdownByURL[ReaderFileRouting.normalizedFileURL(fileURL)] == nil)
        #expect(batch?.openOrigin == .folderWatchAutoOpen)
        #expect(!coordinator.hasPendingEvents)
    }

    @Test @MainActor func folderWatchEventDispatchCoordinatorFallsBackToPrimaryOpenWhenAdditionalHandlerIsMissing() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            options: .default,
            startedAt: Date(timeIntervalSince1970: 99)
        )
        let events = [
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/first.md"), kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/second.md"), kind: .added)
        ]
        var openedPrimaryEvents: [ReaderFolderWatchChangeEvent] = []

        let dispatcher = ReaderFolderWatchDispatcher(
            folderWatchDependencies: ReaderFolderWatchDependencies(
                autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                systemNotifier: TestReaderSystemNotifier()
            )
        )
        dispatcher.setSession(session)
        dispatcher.handleObservedWatchedFolderChanges(
            events,
            currentDocumentFileURL: nil
        ) { event, _, _ in
            openedPrimaryEvents.append(event)
        }

        // Without an additional handler, only the first planned event is opened via primary
        #expect(openedPrimaryEvents.count == 1)
        #expect(openedPrimaryEvents.first?.fileURL == events.first?.fileURL)
    }

    @Test @MainActor func folderWatchEventDispatchCoordinatorUsesAdditionalHandlerForLiveEventsWhenConfigured() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            options: .default,
            startedAt: Date(timeIntervalSince1970: 99)
        )
        let events = [
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/first.md"), kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/second.md"), kind: .modified, previousMarkdown: "# before")
        ]
        var additionalOpenEvents: [ReaderFolderWatchChangeEvent] = []
        var openedPrimaryEvents: [ReaderFolderWatchChangeEvent] = []

        let dispatcher = ReaderFolderWatchDispatcher(
            folderWatchDependencies: ReaderFolderWatchDependencies(
                autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                systemNotifier: TestReaderSystemNotifier()
            )
        )
        dispatcher.setSession(session)
        dispatcher.setAdditionalOpenHandler { event, _, _ in
            additionalOpenEvents.append(event)
        }

        dispatcher.handleObservedWatchedFolderChanges(
            events,
            currentDocumentFileURL: nil
        ) { event, _, _ in
            openedPrimaryEvents.append(event)
        }

        #expect(openedPrimaryEvents.isEmpty)
        #expect(additionalOpenEvents.count == events.count)
        #expect(additionalOpenEvents.map(\.fileURL) == events.map(\.fileURL))
    }

    @Test @MainActor func folderWatchEventDispatchCoordinatorDispatchesInitialBatchAsPrimaryThenAdditional() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            options: .default,
            startedAt: Date(timeIntervalSince1970: 99)
        )
        let events = [
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/first.md"), kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/second.md"), kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: URL(fileURLWithPath: "/tmp/watched/third.md"), kind: .added)
        ]
        var primaryOpenCalls: [(ReaderFolderWatchChangeEvent, ReaderOpenOrigin)] = []
        var additionalOpenCalls: [(ReaderFolderWatchChangeEvent, ReaderOpenOrigin)] = []

        let dispatcher = ReaderFolderWatchDispatcher(
            folderWatchDependencies: ReaderFolderWatchDependencies(
                autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                systemNotifier: TestReaderSystemNotifier()
            )
        )
        dispatcher.setAdditionalOpenHandler { event, _, origin in
            additionalOpenCalls.append((event, origin))
        }

        dispatcher.openInitialMarkdownFilesFromWatchedFolder(
            events,
            session: session
        ) { event, _, origin in
            primaryOpenCalls.append((event, origin))
        }

        #expect(primaryOpenCalls.count == 1)
        #expect(primaryOpenCalls.first?.0 == events[0])
        #expect(primaryOpenCalls.first?.1 == .folderWatchInitialBatchAutoOpen)
        #expect(additionalOpenCalls.map(\.0) == Array(events.dropFirst()))
        #expect(additionalOpenCalls.map(\.1) == [.folderWatchInitialBatchAutoOpen, .folderWatchInitialBatchAutoOpen])
    }

    @Test @MainActor func folderWatchAutoOpenPlannerUsesAgedBaselineForRapidSuccessiveModifications() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let planner = ReaderFolderWatchAutoOpenPlanner(
            minimumDiffBaselineAge: 0.2,
            nowProvider: { now }
        )
        let fileURL = URL(fileURLWithPath: "/tmp/rapid.md")

        let firstEvents = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v0")],
            currentDocumentFileURL: nil
        )
        #expect(firstEvents.first?.previousMarkdown == "# v0")

        now.addTimeInterval(0.05)
        _ = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v1")],
            currentDocumentFileURL: nil
        )

        now.addTimeInterval(0.05)
        let thirdEvents = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v2")],
            currentDocumentFileURL: nil
        )

        #expect(thirdEvents.first?.previousMarkdown == "# v0")

        now.addTimeInterval(0.25)
        let fourthEvents = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v3")],
            currentDocumentFileURL: nil
        )

        #expect(fourthEvents.first?.previousMarkdown == "# v2")
    }

    @Test func folderWatchAutoOpenPlannerCapsLiveBurstSize() {
        let planner = ReaderFolderWatchAutoOpenPlanner()
        let folderURL = URL(fileURLWithPath: "/tmp/watched")
        let session = ReaderFolderWatchSession(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
            startedAt: .now
        )
        let events = (0..<(ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount + 5)).map { index in
            ReaderFolderWatchChangeEvent(
                fileURL: folderURL.appendingPathComponent(String(format: "changed-%02d.md", index)),
                kind: .added
            )
        }

        let plan = planner.livePlan(
            for: events,
            activeSession: session,
            currentDocumentFileURL: nil
        )

        #expect(plan.autoOpenEvents.count == ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)
        #expect(plan.autoOpenEvents.map(\ .fileURL) == Array(events.prefix(ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)).map(\ .fileURL))
        #expect(plan.warning?.folderURL == folderURL)
        #expect(plan.warning?.autoOpenedFileCount == ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)
        #expect(plan.warning?.omittedFileURLs == Array(events.dropFirst(ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)).map(\ .fileURL))
    }

    @Test @MainActor func folderWatchWarningCoordinatorWaitsUntilPresentationIsAllowed() async {
        let coordinator = ReaderFolderWatchAutoOpenWarningCoordinator()
        let omittedFileURL = URL(fileURLWithPath: "/tmp/watched/extra.md")
        let warning = ReaderFolderWatchAutoOpenWarning(
            folderURL: URL(fileURLWithPath: "/tmp/watched"),
            autoOpenedFileCount: 12,
            omittedFileURLs: [omittedFileURL]
        )
        var canPresent = false
        var clearedPersistedWarning = false

        coordinator.handleWarningChange(warning) {
            canPresent
        }

        try? await Task.sleep(for: .milliseconds(120))
        #expect(coordinator.activeFlow == nil)

        canPresent = true

        try? await Task.sleep(for: .milliseconds(120))
        #expect(coordinator.activeFlow?.warning == warning)
        #expect(coordinator.selectedFileURLs().isEmpty)

        coordinator.activeFlow?.selectionModel.clearSelection()
        #expect(coordinator.selectedFileURLs().isEmpty)

        coordinator.dismiss {
            clearedPersistedWarning = true
        }

        #expect(clearedPersistedWarning)
        #expect(coordinator.activeFlow == nil)
    }

    @Test func folderWatchStatusLabelStaysCompactAndTooltipCarriesFullDetails() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/Users/example/Documents/Projects/MarkdownObserver/docs/reference", isDirectory: true),
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            ),
            startedAt: Date(timeIntervalSince1970: 4242)
        )

        #expect(session.chipLabel == "Watching folder: reference")
        #expect(session.statusLabel == "Watching reference")
        #expect(session.detailSummaryTitle == "reference")
        #expect(session.detailPathText == "/Users/example/Documents/Projects/MarkdownObserver/docs/reference")
        #expect(session.detailRows.count == 3)
        #expect(session.detailRows[0].title == "When watch starts")
        #expect(session.detailRows[0].value == "Open all Markdown files")
        #expect(session.detailRows[1].title == "Scope")
        #expect(session.detailRows[1].value == "Include subfolders")
        #expect(session.detailRows[2].title == "Filtered subdirectories")
        #expect(session.detailRows[2].value == "0")
        #expect(!session.statusLabel.contains(session.options.openMode.label))
        #expect(!session.statusLabel.contains(session.options.scope.label))
        #expect(session.titleLabel == session.chipLabel)
        #expect(session.tooltipText.contains("Watching folder"))
        #expect(session.tooltipText.contains(session.detailPathText))
        #expect(session.tooltipText.contains("When watch starts: Open all Markdown files"))
        #expect(session.tooltipText.contains("Scope: Include subfolders"))
        #expect(session.tooltipText.contains("Filtered subdirectories: 0"))
    }

    @Test func folderWatchTooltipOmitsFilteredSubdirectoryLineForSelectedFolderScope() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/Users/example/Documents/Projects/MarkdownObserver/docs/reference", isDirectory: true),
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly,
                excludedSubdirectoryPaths: ["/Users/example/Documents/Projects/MarkdownObserver/docs/reference/build"]
            ),
            startedAt: Date(timeIntervalSince1970: 4242)
        )

        #expect(session.detailRows.count == 2)
        #expect(!session.tooltipText.contains("Filtered subdirectories:"))
    }

    @Test func windowTitleFormatterUsesDocumentTitleWithoutWatch() {
        let title = ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: "guide.md - MarkdownObserver",
            activeFolderWatch: nil,
            hasUnacknowledgedExternalChange: false
        )

        #expect(title == "guide.md - MarkdownObserver")
    }

    @Test func windowTitleFormatterShowsWatchStateAndPreservesPendingMarker() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/guides", isDirectory: true),
            options: .default,
            startedAt: Date(timeIntervalSince1970: 11)
        )

        let title = ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: "guide.md - MarkdownObserver",
            activeFolderWatch: session,
            hasUnacknowledgedExternalChange: true
        )

        #expect(title == "* guide.md - MarkdownObserver")
    }

    @Test func documentIndicatorStateDistinguishesDeletedDocumentsFromOtherExternalChanges() {
        #expect(
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: false,
                isCurrentFileMissing: false
            ) == .none
        )
        #expect(
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: true,
                isCurrentFileMissing: false,
                unacknowledgedExternalChangeKind: .modified
            ) == .externalChange
        )
        #expect(
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: true,
                isCurrentFileMissing: false,
                unacknowledgedExternalChangeKind: .added
            ) == .addedExternalChange
        )
        #expect(
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: true,
                isCurrentFileMissing: true
            ) == .deletedExternalChange
        )
    }

    @Test func documentIndicatorColorsUseNativeSystemPalette() throws {
        let addedColor = ReaderDocumentIndicatorState.addedExternalChange.color(
            for: .default,
            colorScheme: .light
        )
        let externalColor = ReaderDocumentIndicatorState.externalChange.color(
            for: .default,
            colorScheme: .light
        )
        let deletedColor = ReaderDocumentIndicatorState.deletedExternalChange.color(
            for: .default,
            colorScheme: .dark
        )

        let resolvedAdded = try #require(NSColor(addedColor).usingColorSpace(.deviceRGB))
        let resolvedExternal = try #require(NSColor(externalColor).usingColorSpace(.deviceRGB))
        let resolvedDeleted = try #require(NSColor(deletedColor).usingColorSpace(.deviceRGB))
        let expectedAdded = try #require(NSColor.systemGreen.usingColorSpace(.deviceRGB))
        let expectedExternal = try #require(NSColor.systemYellow.usingColorSpace(.deviceRGB))
        let expectedDeleted = try #require(NSColor.systemRed.usingColorSpace(.deviceRGB))

        #expect(abs(resolvedAdded.redComponent - expectedAdded.redComponent) < 0.002)
        #expect(abs(resolvedAdded.greenComponent - expectedAdded.greenComponent) < 0.002)
        #expect(abs(resolvedAdded.blueComponent - expectedAdded.blueComponent) < 0.002)
        #expect(abs(resolvedAdded.alphaComponent - expectedAdded.alphaComponent) < 0.002)

        #expect(abs(resolvedExternal.redComponent - expectedExternal.redComponent) < 0.002)
        #expect(abs(resolvedExternal.greenComponent - expectedExternal.greenComponent) < 0.002)
        #expect(abs(resolvedExternal.blueComponent - expectedExternal.blueComponent) < 0.002)
        #expect(abs(resolvedExternal.alphaComponent - expectedExternal.alphaComponent) < 0.002)

        #expect(abs(resolvedDeleted.redComponent - expectedDeleted.redComponent) < 0.002)
        #expect(abs(resolvedDeleted.greenComponent - expectedDeleted.greenComponent) < 0.002)
        #expect(abs(resolvedDeleted.blueComponent - expectedDeleted.blueComponent) < 0.002)
        #expect(abs(resolvedDeleted.alphaComponent - expectedDeleted.alphaComponent) < 0.002)
    }

    @Test @MainActor func focusDocumentIfAlreadyOpenUsesRegisteredWindowFocusHandler() {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let requestedURL = URL(fileURLWithPath: "/tmp/sidebar/open.md")
        var focusedURLs: [URL] = []

        ReaderWindowRegistry.shared.registerWindow(
            window,
            focusDocument: { fileURL in
                focusedURLs.append(fileURL)
                return fileURL == ReaderFileRouting.normalizedFileURL(requestedURL)
            },
            watchedFolderURLProvider: { nil }
        )

        let didFocus = ReaderWindowRegistry.shared.focusDocumentIfAlreadyOpen(at: requestedURL)

        #expect(didFocus)
        #expect(focusedURLs == [ReaderFileRouting.normalizedFileURL(requestedURL)])
    }

    @Test @MainActor func openAdditionalDocumentInCurrentWindowBypassesGlobalRegistryFocus() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-window-local-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let markdownURL = temporaryDirectoryURL.appendingPathComponent("alpha.md")
        try "# Alpha".write(to: markdownURL, atomically: true, encoding: .utf8)

        let foreignWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        var focusedURLs: [URL] = []
        ReaderWindowRegistry.shared.registerWindow(
            foreignWindow,
            focusDocument: { fileURL in
                focusedURLs.append(fileURL)
                return true
            },
            watchedFolderURLProvider: { nil }
        )

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.window-local-open.\(UUID().uuidString)"
        )
        let view = ReaderWindowRootView(
            seed: nil,
            settingsStore: settingsStore,
            multiFileDisplayMode: .sidebarLeft
        )

        view.windowCoordinator.openAdditionalDocumentInCurrentWindow(markdownURL)

        #expect(focusedURLs.isEmpty)
        #expect(view.sidebarDocumentController.selectedReaderStore.document.fileURL?.path == markdownURL.path)
    }

    @Test @MainActor func openAdditionalDocumentsInCurrentWindowKeepsBatchLocal() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-window-local-batch-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }

        let alphaURL = temporaryDirectoryURL.appendingPathComponent("alpha.md")
        let zetaURL = temporaryDirectoryURL.appendingPathComponent("zeta.md")
        try "# Alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try "# Zeta".write(to: zetaURL, atomically: true, encoding: .utf8)

        let foreignWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        var focusedURLs: [URL] = []
        ReaderWindowRegistry.shared.registerWindow(
            foreignWindow,
            focusDocument: { fileURL in
                focusedURLs.append(fileURL)
                return true
            },
            watchedFolderURLProvider: { nil }
        )

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.window-local-batch-open.\(UUID().uuidString)"
        )
        let view = ReaderWindowRootView(
            seed: nil,
            settingsStore: settingsStore,
            multiFileDisplayMode: .sidebarLeft
        )

        view.windowCoordinator.openFileRequest(FileOpenRequest(
            fileURLs: [zetaURL, alphaURL],
            origin: .manual,
            slotStrategy: .reuseEmptySlotForFirst
        ))

        #expect(focusedURLs.isEmpty)
        #expect(Set(view.sidebarDocumentController.documents.compactMap { $0.readerStore.document.fileURL?.path }) == Set([
            alphaURL.path,
            zetaURL.path
        ]))
        #expect(view.sidebarDocumentController.selectedReaderStore.document.fileURL?.path == zetaURL.path)
    }

    @Test @MainActor func readerWindowCoordinatorResolvesTitleFromSelectedDocumentState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        coordinator.applyWindowTitlePresentation()

        let expectedTitle = ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: harness.controller.selectedWindowTitle,
            activeFolderWatch: nil,
            hasUnacknowledgedExternalChange: harness.controller.selectedHasUnacknowledgedExternalChange
        )
        #expect(coordinator.effectiveWindowTitle == expectedTitle)
    }

    @Test @MainActor func readerWindowCoordinatorQueuesFolderWatchOpenEventsUntilFlushIsPossible() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )
        let queuedURL = URL(fileURLWithPath: "/tmp/queued-from-window-coordinator.md")
        let queuedEvent = ReaderFolderWatchChangeEvent(
            fileURL: queuedURL,
            kind: .modified,
            previousMarkdown: "# Before"
        )

        coordinator.enqueueFolderWatchOpen(
            queuedEvent,
            folderWatchSession: nil,
            origin: .folderWatchAutoOpen
        )

        #expect(coordinator.hasPendingFolderWatchOpenEvents)

        // Without a host window, flush should not consume the queued events
        coordinator.flushQueuedFolderWatchOpens()
        #expect(coordinator.hasPendingFolderWatchOpenEvents)
    }

    @Test @MainActor func folderWatchControllerDoesNotSetWarningForLiveEventsExceedingLimit() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-\(UUID().uuidString)", isDirectory: true)
        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.live-no-warning.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
        let delegate = TestFolderWatchControllerDelegate()
        controller.delegate = delegate

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly
            )
        )

        let liveEvents = (0..<(ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount + 5)).map { index in
            ReaderFolderWatchChangeEvent(
                fileURL: folderURL.appendingPathComponent(String(format: "live-%02d.md", index)),
                kind: .added
            )
        }
        watcher.emitChangedMarkdownEvents(liveEvents)

        try await Task.sleep(for: .milliseconds(50))

        #expect(controller.folderWatchAutoOpenWarning == nil)
        #expect(delegate.handledEvents.count == ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)
    }

    @Test @MainActor func liveAutoOpenNotifiesDelegateWithAutoOpenedFileURLs() async throws {
        let folderURL = URL(fileURLWithPath: "/tmp/watched-live-indicator", isDirectory: true)
        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.folder-watch.live-indicator.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
        let delegate = TestFolderWatchControllerDelegate()
        controller.delegate = delegate

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly
            )
        )

        let newFileURL = folderURL.appendingPathComponent("new-file.md")
        watcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(fileURL: newFileURL, kind: .added)
        ])

        try await Task.sleep(for: .milliseconds(50))

        #expect(delegate.liveAutoOpenedURLs.count == 1)
        #expect(delegate.liveAutoOpenedURLs.first?.lastPathComponent == "new-file.md")
    }

    @Test @MainActor func focusNotificationTargetFallsBackToWatchedFolderWindow() {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let watchedFolderURL = URL(fileURLWithPath: "/tmp/watched-folder", isDirectory: true)

        ReaderWindowRegistry.shared.registerWindow(
            window,
            focusDocument: { _ in false },
            watchedFolderURLProvider: { watchedFolderURL }
        )

        #expect(
            ReaderWindowRegistry.shared.focusNotificationTarget(
                fileURL: nil,
                watchedFolderURL: watchedFolderURL
            )
        )
    }
}
