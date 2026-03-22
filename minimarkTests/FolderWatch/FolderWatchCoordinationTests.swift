//
//  FolderWatchCoordinationTests.swift
//  minimarkTests
//

import AppKit
import Foundation
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

    @Test @MainActor func burstOpenPlanningNormalizesDeduplicatesAndSorts() {
        let urls: [URL] = [
            URL(fileURLWithPath: "/tmp/zeta.md"),
            URL(fileURLWithPath: "/tmp/alpha.md"),
            URL(fileURLWithPath: "/tmp/alpha.md"),
            URL(fileURLWithPath: "/tmp/notes.markdown")
        ]

        let planned = ReaderFileRouting.plannedOpenFileURLs(from: urls)

        #expect(planned.map(\.path) == [
            "/tmp/alpha.md",
            "/tmp/notes.markdown",
            "/tmp/zeta.md"
        ])
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

    @Test @MainActor func folderWatchAutoOpenPlannerUsesAgedBaselineForRapidSuccessiveModifications() async {
        let planner = ReaderFolderWatchAutoOpenPlanner(minimumDiffBaselineAge: 0.2)
        let fileURL = URL(fileURLWithPath: "/tmp/rapid.md")

        let firstEvents = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v0")],
            currentDocumentFileURL: nil
        )
        #expect(firstEvents.first?.previousMarkdown == "# v0")

        try? await Task.sleep(for: .milliseconds(50))
        _ = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v1")],
            currentDocumentFileURL: nil
        )

        try? await Task.sleep(for: .milliseconds(50))
        let thirdEvents = planner.liveOpenEvents(
            for: [ReaderFolderWatchChangeEvent(fileURL: fileURL, kind: .modified, previousMarkdown: "# v2")],
            currentDocumentFileURL: nil
        )

        #expect(thirdEvents.first?.previousMarkdown == "# v0")

        try? await Task.sleep(for: .milliseconds(250))
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
        #expect(coordinator.selectedFileURLs() == [omittedFileURL])

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
        #expect(session.detailRows.count == 2)
        #expect(session.detailRows[0].title == "When watch starts")
        #expect(session.detailRows[0].value == "Open all Markdown files")
        #expect(session.detailRows[1].title == "Scope")
        #expect(session.detailRows[1].value == "Include subfolders")
        #expect(!session.statusLabel.contains(session.options.openMode.label))
        #expect(!session.statusLabel.contains(session.options.scope.label))
        #expect(session.titleLabel == session.chipLabel)
        #expect(session.tooltipText.contains("Watching folder"))
        #expect(session.tooltipText.contains(session.detailPathText))
        #expect(session.tooltipText.contains("When watch starts: Open all Markdown files"))
        #expect(session.tooltipText.contains("Scope: Include subfolders"))
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

        #expect(title == "* guide.md - MarkdownObserver | Watching folder: guides")
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
                isCurrentFileMissing: false
            ) == .externalChange
        )
        #expect(
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: true,
                isCurrentFileMissing: true
            ) == .deletedExternalChange
        )
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
