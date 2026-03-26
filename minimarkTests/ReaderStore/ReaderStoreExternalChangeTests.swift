//
//  ReaderStoreExternalChangeTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreExternalChangeTests {
    @Test @MainActor func handleObservedFileChangeSetsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(!fixture.store.hasUnacknowledgedExternalChange)

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.store.lastExternalChangeAt != nil)
    }

    @Test @MainActor func statusBarTimestampUsesFilesystemModificationTimeAndPrefersExternalChangeTime() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        #expect(fixture.store.statusBarTimestamp == nil)

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.store.statusBarTimestamp == .lastModified(fixture.store.fileLastModifiedAt!))

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.statusBarTimestamp == .updated(fixture.store.lastExternalChangeAt!))
    }

    @Test @MainActor func handleObservedFileChangePostsSystemNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.notifier.externalChangeNotifications == [
            TestReaderSystemNotifier.ExternalChangeNotification(
                fileURL: ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL),
                autoRefreshed: false,
                watchedFolderURL: nil
            )
        ])
    }

    @Test @MainActor func handleObservedFileChangeSkipsSystemNotificationWhenDisabled() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            notificationsEnabled: false
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.notifier.externalChangeNotifications.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenSkipsSystemNotificationWhenDisabled() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            notificationsEnabled: false
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.notifier.autoLoadedNotifications.isEmpty)
    }

    @Test @MainActor func decoratedWindowTitlePrependsAsteriskOnlyWhenPending() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.store.decoratedWindowTitle == "\(fixture.store.windowTitle)")
        #expect(!fixture.store.decoratedWindowTitle.hasPrefix("* "))

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.decoratedWindowTitle == "* \(fixture.store.windowTitle)")
    }

    @Test @MainActor func readerStoreKeepsDocumentViewModeInPreviewWithoutOpenDocument() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        #expect(fixture.store.documentViewMode == .preview)

        fixture.store.setDocumentViewMode(.split)

        #expect(fixture.store.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCanSwitchToSourceAndResetsToPreviewForNewFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.setDocumentViewMode(.source)

        #expect(fixture.store.documentViewMode == .source)

        fixture.store.openFile(at: fixture.secondaryFileURL)

        #expect(fixture.store.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCanSwitchToSplitAndResetsToPreviewForNewFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.setDocumentViewMode(.split)

        #expect(fixture.store.documentViewMode == .split)

        fixture.store.openFile(at: fixture.secondaryFileURL)

        #expect(fixture.store.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCyclesDocumentViewModesInPreviewSplitSourceOrder() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.store.documentViewMode == .preview)

        fixture.store.toggleDocumentViewMode()
        #expect(fixture.store.documentViewMode == .split)

        fixture.store.toggleDocumentViewMode()
        #expect(fixture.store.documentViewMode == .source)

        fixture.store.toggleDocumentViewMode()
        #expect(fixture.store.documentViewMode == .preview)
    }

    @Test @MainActor func manualReloadCurrentFileClearsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.hasUnacknowledgedExternalChange)

        fixture.write(content: "# Updated", to: fixture.primaryFileURL)
        fixture.store.reloadCurrentFile(forceHighlight: true, acknowledgeExternalChange: true)

        #expect(!fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func autoRefreshEnabledReloadsContentButKeepsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        #expect(fixture.store.sourceMarkdown == "# Initial")

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.sourceMarkdown == "# Modified")
        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func externalDeletionMarksOpenDocumentAsMissingEvenWhenAutoRefreshIsDisabled() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        let originalMarkdown = fixture.store.sourceMarkdown
        let originalHTML = fixture.store.renderedHTMLDocument
        fixture.delete(fixture.primaryFileURL)

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.isCurrentFileMissing)
        #expect(fixture.store.fileURL == ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL))
        #expect(fixture.store.sourceMarkdown == originalMarkdown)
        #expect(fixture.store.renderedHTMLDocument == originalHTML)
        #expect(fixture.store.lastError?.contains("Failed to read file") == true)
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func recreatedMissingDocumentClearsMissingStateOnNextObservedChange() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.delete(fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.isCurrentFileMissing)

        fixture.write(content: "# Restored", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(!fixture.store.isCurrentFileMissing)
        #expect(fixture.store.sourceMarkdown == "# Restored")
    }

    @Test @MainActor func folderWatchAutoOpenIgnoresInitialWatcherNoiseWhenContentIsUnchanged() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)
        #expect(fixture.store.changedRegions.isEmpty)

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.sourceMarkdown == "# Initial")
        #expect(fixture.store.changedRegions.isEmpty)
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.store.lastExternalChangeAt == nil)
    }

    @Test @MainActor func folderWatchAutoOpenAddedFileDoesNotHighlightItsInitialSettlingWrite() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions.isEmpty)
        #expect(fixture.store.sourceMarkdown == "# Updated Once")
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchModifiedFileAutoOpenShowsChangedRegionsImmediately() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)

        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Initial"
        )

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceMarkdown == "# Updated Once")
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenWithoutOwnedWatchDoesNotPostDuplicateSystemNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.notifier.autoLoadedNotifications.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenStillHighlightsAfterIgnoredInitialWatcherNoise() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.store.handleObservedFileChange()
        #expect(fixture.store.changedRegions.isEmpty)
        #expect(fixture.store.sourceMarkdown == "# Initial")

        fixture.write(content: "# Updated Again", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceMarkdown == "# Updated Again")
    }

    @Test @MainActor func folderWatchModifiedFileAutoOpenStillHighlightsLaterExternalRefresh() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)
        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Initial"
        )

        fixture.store.handleObservedFileChange()
        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])

        fixture.write(content: "# Updated Twice", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceMarkdown == "# Updated Twice")
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenAddedFileAbsorbsInitialChangedContentWithoutIndicators() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.write(content: "# Settled Initial Content", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions.isEmpty)
        #expect(fixture.store.sourceMarkdown == "# Settled Initial Content")
        #expect(!fixture.store.hasUnacknowledgedExternalChange)

        fixture.write(content: "# Real Follow Up Change", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceMarkdown == "# Real Follow Up Change")
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenRecoversContentWhenInitialSettlingWriteMissesWatcherEvent() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion],
            autoOpenSettlingInterval: 0.4
        )
        defer { fixture.cleanup() }

        fixture.write(content: "", to: fixture.primaryFileURL)

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)
        #expect(fixture.store.sourceMarkdown.isEmpty)
        #expect(fixture.store.documentLoadState == .settlingAutoOpen)

        fixture.write(content: "# Settled Initial Content", to: fixture.primaryFileURL)

        let settled = await waitUntil(timeout: .seconds(1)) {
            fixture.store.sourceMarkdown == "# Settled Initial Content"
        }

        #expect(settled)
        #expect(fixture.store.changedRegions.isEmpty)
        #expect(fixture.store.documentLoadState == .ready)
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenEmptyFileKeepsSettlingStateUntilContentArrives() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            autoOpenSettlingInterval: 0.02
        )
        defer { fixture.cleanup() }

        fixture.write(content: "", to: fixture.primaryFileURL)

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.store.documentLoadState == .settlingAutoOpen)

        try? await Task.sleep(for: .milliseconds(60))

        #expect(fixture.store.documentLoadState == .settlingAutoOpen)
        #expect(fixture.store.sourceMarkdown.isEmpty)

        fixture.write(content: "# Arrived Later", to: fixture.primaryFileURL)

        let settled = await waitUntil(timeout: .seconds(1)) {
            fixture.store.documentLoadState == .ready && fixture.store.sourceMarkdown == "# Arrived Later"
        }

        #expect(settled)
        #expect(fixture.store.changedRegions.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenedAddedFileHighlightsExternalRefreshAfterSettlingWindowExpires() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion],
            autoOpenSettlingInterval: 0.01
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        try? await Task.sleep(for: .milliseconds(30))

        fixture.write(content: "# Later External Change", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceMarkdown == "# Later External Change")
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func manualOpenStillHighlightsOnFirstExternalRefresh() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL, origin: .manual)

        #expect(fixture.store.documentLoadState == .ready)

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
    }

        @Test @MainActor func manualOpenWithinWatchedFolderUsesFolderScopeWithoutRetryingChildFileScope() throws {
            let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
            defer { fixture.cleanup() }

            let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
            let session = ReaderFolderWatchSession(
                folderURL: fixture.temporaryDirectoryURL,
                options: options,
                startedAt: .now
            )
            fixture.settings.addRecentWatchedFolder(fixture.temporaryDirectoryURL, options: options)
            fixture.securityScope.didStartAccessResponsesByPath[fixture.primaryFileURL.path] = [false]

            fixture.store.openFile(
                at: fixture.primaryFileURL,
                origin: .manual,
                folderWatchSession: session
            )

            #expect(fixture.store.sourceMarkdown == "# Initial")
            #expect(
                fixture.securityScope.accessedURLs.map(ReaderFileRouting.normalizedFileURL) == [
                    ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL),
                    ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL)
                ]
            )
        }

    @Test @MainActor func openingFileClearsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.hasUnacknowledgedExternalChange)

        fixture.store.openFile(at: fixture.secondaryFileURL)

        #expect(!fixture.store.hasUnacknowledgedExternalChange)
        #expect(!fixture.store.decoratedWindowTitle.hasPrefix("* "))
    }

    @Test @MainActor func openingSecondFileStopsPreviousWatcherBeforeRebinding() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.openFile(at: fixture.secondaryFileURL)

        #expect(fixture.watcher.operations == [
            .stop,
            .start(ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL)),
            .stop,
            .start(ReaderFileRouting.normalizedFileURL(fixture.secondaryFileURL))
        ])
    }

    @Test @MainActor func failedOpenPreservesCurrentFileWatcherAndAvoidsDuplicateRebinds() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        let initialStartCallCount = fixture.watcher.startCallCount
        let initialStopCallCount = fixture.watcher.stopCallCount

        let missingFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("missing.md")
        fixture.store.openFile(at: missingFileURL)
        fixture.store.openFile(at: missingFileURL)

        #expect(fixture.store.fileURL == ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL))
        #expect(fixture.watcher.startCallCount == initialStartCallCount)
        #expect(fixture.watcher.stopCallCount == initialStopCallCount)
        #expect(!fixture.store.hasUnacknowledgedExternalChange)

        fixture.watcher.emitChange()
        await Task.yield()

        #expect(fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.externalChangeNotifications.count == 1)
    }

    @Test @MainActor func autoRefreshDisabledStillMarksExternalChangeAsPending() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        #expect(fixture.store.sourceMarkdown == "# Initial")

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.store.sourceMarkdown == "# Initial")
    }

    @Test @MainActor func startWatchingFolderSetsActiveSession() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let options = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .includeSubfolders
        )

        fixture.store.startWatchingFolder(folderURL: fixture.temporaryDirectoryURL, options: options)

        #expect(fixture.store.activeFolderWatchSession?.folderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.store.activeFolderWatchSession?.options == options)
        #expect(fixture.folderWatcher.startCallCount == 1)
        #expect(fixture.folderWatcher.lastIncludeSubfolders == true)
    }

    @Test @MainActor func currentWatchedFileRetainsDedicatedFileWatcherOwnership() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: .default
        )

        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: fixture.store.activeFolderWatchSession
        )

        #expect(fixture.watcher.startCallCount == 1)
        #expect(fixture.watcher.lastStartedFileURL == ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL))
    }

    @Test @MainActor func watchedFolderEventForCurrentFileDoesNotTriggerExternalChangeWhenFileWatcherOwnsCurrentFile() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: .default
        )
        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: fixture.store.activeFolderWatchSession
        )

        fixture.folderWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(
                fileURL: fixture.primaryFileURL,
                kind: .modified,
                previousMarkdown: "# Initial"
            )
        ])

        await Task.yield()

        #expect(!fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.externalChangeNotifications.isEmpty)
        #expect(fixture.watcher.startCallCount == 1)
    }

    @Test @MainActor func fileWatcherEventForWatchedCurrentFileTriggersExternalChange() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: .default
        )
        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: fixture.store.activeFolderWatchSession
        )

        fixture.watcher.emitChange()
        await Task.yield()

        #expect(fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.externalChangeNotifications.count == 1)
    }

    @Test @MainActor func watchChangesOnlyDoesNotAutoOpenExistingMarkdownFilesWhenIncludingSubfolders() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let nestedDirectoryURL = fixture.temporaryDirectoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)

        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("existing.md")
        fixture.write(content: "# Nested", to: nestedFileURL)
        fixture.folderWatcher.markdownFilesToReturn = [fixture.primaryFileURL, nestedFileURL]

        var openedAdditionalDocuments: [URL] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            openedAdditionalDocuments.append(ReaderFileRouting.normalizedFileURL(event.fileURL))
        }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        )

        #expect(fixture.store.fileURL == nil)
        #expect(openedAdditionalDocuments.isEmpty)
        #expect(fixture.notifier.autoLoadedNotifications.isEmpty)
    }

    @Test @MainActor func recursiveWatchedFolderDoesNotMarkCurrentNestedDocumentChangedWithoutRealEdits() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-reader-store-real-watchers-\(UUID().uuidString)", isDirectory: true)
        let nestedDirectoryURL = directoryURL
            .appendingPathComponent(".github", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("README.md")
        try "# Initial".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        let settings = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        let notifier = TestReaderSystemNotifier()
        let settler = ReaderAutoOpenSettler(settlingInterval: 0.2)
        let store = ReaderStore(
            renderer: TestMarkdownRenderer(),
            differ: TestChangedRegionDiffer(),
            fileWatcher: FileChangeWatcher(
                pollingInterval: .milliseconds(50),
                fallbackPollingInterval: .milliseconds(80),
                verificationDelay: .milliseconds(20)
            ),
            folderWatcher: FolderChangeWatcher(
                pollingInterval: .milliseconds(50),
                fallbackPollingInterval: .milliseconds(80),
                verificationDelay: .milliseconds(20)
            ),
            settingsStore: settings,
            securityScope: TestSecurityScopeAccess(),
            fileActions: TestReaderFileActions(),
            systemNotifier: notifier,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
            settler: settler
        )

        store.handleIncomingOpenURL(nestedFileURL, origin: .manual)
        store.startWatchingFolder(
            folderURL: directoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        )

        try? await Task.sleep(for: .milliseconds(500))

        #expect(store.fileURL == ReaderFileRouting.normalizedFileURL(nestedFileURL))
        #expect(store.lastExternalChangeAt == nil)
        #expect(!store.hasUnacknowledgedExternalChange)
        #expect(notifier.externalChangeNotifications.isEmpty)
    }

    @Test @MainActor func stopWatchingFolderClearsSessionAndStopsWatcher() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: .default
        )
        #expect(fixture.store.activeFolderWatchSession != nil)

        fixture.store.stopWatchingFolder()

        #expect(fixture.store.activeFolderWatchSession == nil)
        #expect(fixture.folderWatcher.stopCallCount >= 1)
    }

    @Test @MainActor func openAllMarkdownFilesOpensFirstInCurrentWindowAndOthersAsAdditionalDocuments() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let thirdFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("third.md")
        fixture.write(content: "# Third", to: thirdFileURL)

        fixture.folderWatcher.markdownFilesToReturn = [
            fixture.secondaryFileURL,
            fixture.primaryFileURL,
            thirdFileURL
        ]

        var openedAdditionalDocuments: [URL] = []
        var openedOrigins: [ReaderOpenOrigin] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, origin in
            openedAdditionalDocuments.append(ReaderFileRouting.normalizedFileURL(event.fileURL))
            openedOrigins.append(origin)
        }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(fixture.store.fileURL == ReaderFileRouting.normalizedFileURL(fixture.secondaryFileURL))
        #expect(openedAdditionalDocuments == [
            ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL),
            ReaderFileRouting.normalizedFileURL(thirdFileURL)
        ])
        #expect(openedOrigins == [.folderWatchInitialBatchAutoOpen, .folderWatchInitialBatchAutoOpen])
        #expect(fixture.store.folderWatchAutoOpenWarning == nil)
        #expect(fixture.notifier.autoLoadedNotifications.isEmpty)
    }

    @Test @MainActor func openAllMarkdownFilesSingleInitialAutoOpenStillPostsSystemNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.folderWatcher.markdownFilesToReturn = [fixture.primaryFileURL]

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(fixture.notifier.autoLoadedNotifications == [
            TestReaderSystemNotifier.AutoLoadedNotification(
                fileURL: ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .added,
                watchedFolderURL: ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL)
            )
        ])
    }

    @Test @MainActor func openAllMarkdownFilesCapsInitialAutoOpenAndPublishesWarning() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let autoOpenLimit = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
        let additionalFileCount = 3
        let fileURLs = (0..<(autoOpenLimit + additionalFileCount)).map { index in
            let fileURL = fixture.temporaryDirectoryURL.appendingPathComponent(String(format: "bulk-%02d.md", index))
            fixture.write(content: "# File \(index)", to: fileURL)
            return fileURL
        }

        fixture.folderWatcher.markdownFilesToReturn = fileURLs

        var openedAdditionalDocuments: [URL] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            openedAdditionalDocuments.append(ReaderFileRouting.normalizedFileURL(event.fileURL))
        }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(fixture.store.fileURL == ReaderFileRouting.normalizedFileURL(fileURLs[0]))
        #expect(openedAdditionalDocuments == Array(fileURLs.dropFirst().prefix(autoOpenLimit - 1)).map(ReaderFileRouting.normalizedFileURL))
        #expect(fixture.store.folderWatchAutoOpenWarning?.autoOpenedFileCount == autoOpenLimit)
        #expect(fixture.store.folderWatchAutoOpenWarning?.remainingFileCount == additionalFileCount)
        #expect(fixture.store.folderWatchAutoOpenWarning?.folderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(
            fixture.store.folderWatchAutoOpenWarning?.omittedFileURLs == Array(
                fileURLs.dropFirst(autoOpenLimit)
            ).map(ReaderFileRouting.normalizedFileURL)
        )
    }

    @Test @MainActor func watchedFolderChangesOpenMarkdownAsAdditionalDocuments() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        let fourthFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("fourth.md")
        fixture.write(content: "# Fourth", to: fourthFileURL)
        let unsupportedURL = fixture.temporaryDirectoryURL.appendingPathComponent("skip.txt")
        fixture.write(content: "ignore", to: unsupportedURL)

        var openedAdditionalDocuments: [URL] = []
        var openedEvents: [ReaderFolderWatchChangeEvent] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            openedAdditionalDocuments.append(ReaderFileRouting.normalizedFileURL(event.fileURL))
            openedEvents.append(event)
        }

        fixture.folderWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(fileURL: fixture.primaryFileURL, kind: .modified, previousMarkdown: "# Initial"),
            ReaderFolderWatchChangeEvent(fileURL: fourthFileURL, kind: .added),
            ReaderFolderWatchChangeEvent(fileURL: unsupportedURL, kind: .added)
        ])

        await Task.yield()

        #expect(openedAdditionalDocuments == [ReaderFileRouting.normalizedFileURL(fourthFileURL)])
        #expect(openedEvents[0].kind == .added)
        #expect(openedEvents[0].previousMarkdown == nil)
        #expect(fixture.store.lastWatchedFolderEventAt != nil)
    }

    @Test @MainActor func watchedFolderAddedFilesOpenAsAdditionalDocumentsEvenWhenWatcherOwnerHasNoOpenDocument() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        let createdFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("created.md")
        fixture.write(content: "", to: createdFileURL)

        var openedEvents: [ReaderFolderWatchChangeEvent] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            openedEvents.append(event)
        }

        fixture.folderWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(fileURL: createdFileURL, kind: .added)
        ])

        await Task.yield()

        #expect(fixture.store.fileURL == nil)
        #expect(openedEvents.map(\ .fileURL) == [ReaderFileRouting.normalizedFileURL(createdFileURL)])
        #expect(openedEvents.map(\ .kind) == [.added])
        #expect(fixture.store.lastWatchedFolderEventAt != nil)
    }

    @Test @MainActor func watchedFolderModifiedFilesForwardPreviousMarkdownToAdditionalDocumentCallback() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        let changedFileURL = fixture.secondaryFileURL
        var capturedEvent: ReaderFolderWatchChangeEvent?
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            capturedEvent = event
        }

        fixture.folderWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(
                fileURL: changedFileURL,
                kind: .modified,
                previousMarkdown: "# Second"
            )
        ])

        await Task.yield()

        #expect(capturedEvent?.fileURL == ReaderFileRouting.normalizedFileURL(changedFileURL))
        #expect(capturedEvent?.kind == .modified)
        #expect(capturedEvent?.previousMarkdown == "# Second")
    }

    @Test @MainActor func watchedFolderLiveBurstPublishesWarningForOmittedFiles() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        let autoOpenLimit = ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount
        let fileURLs = (0..<(autoOpenLimit + 2)).map { index in
            let fileURL = fixture.temporaryDirectoryURL.appendingPathComponent(String(format: "live-%02d.md", index))
            fixture.write(content: "# File \(index)", to: fileURL)
            return fileURL
        }

        var openedAdditionalDocuments: [URL] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, _, _ in
            openedAdditionalDocuments.append(ReaderFileRouting.normalizedFileURL(event.fileURL))
        }

        fixture.folderWatcher.emitChangedMarkdownEvents(
            fileURLs.map { ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added) }
        )

        await Task.yield()

        #expect(openedAdditionalDocuments == Array(fileURLs.prefix(autoOpenLimit)).map(ReaderFileRouting.normalizedFileURL))
        #expect(fixture.store.folderWatchAutoOpenWarning?.autoOpenedFileCount == autoOpenLimit)
        #expect(fixture.store.folderWatchAutoOpenWarning?.folderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.store.folderWatchAutoOpenWarning?.omittedFileURLs == Array(fileURLs.dropFirst(autoOpenLimit)).map(ReaderFileRouting.normalizedFileURL))
    }

    @Test @MainActor func folderWatchOpenedAdditionalDocumentsReceiveCurrentWatchSessionInCallback() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let anotherFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("another.md")
        fixture.write(content: "# Another", to: anotherFileURL)

        fixture.folderWatcher.markdownFilesToReturn = [
            fixture.primaryFileURL,
            anotherFileURL
        ]

        var capturedSessions: [ReaderFolderWatchSession?] = []
        fixture.store.setOpenAdditionalDocumentForFolderWatchEventHandler { _, session, _ in
            capturedSessions.append(session)
        }

        let options = ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        fixture.store.startWatchingFolder(folderURL: fixture.temporaryDirectoryURL, options: options)

        #expect(capturedSessions.count == 1)
        #expect(capturedSessions[0] == fixture.store.activeFolderWatchSession)
    }

    @Test @MainActor func stopWatchingFolderDoesNotAffectPendingExternalChangeState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()
        #expect(fixture.store.hasUnacknowledgedExternalChange)

        fixture.store.startWatchingFolder(
            folderURL: fixture.temporaryDirectoryURL,
            options: .default
        )
        #expect(fixture.store.isWatchingFolder)

        fixture.store.stopWatchingFolder()

        #expect(!fixture.store.isWatchingFolder)
        #expect(fixture.store.activeFolderWatchSession == nil)
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }
}

// MARK: - handleIncomingOpenURL deduplication

extension ReaderStoreExternalChangeTests {
    @Test @MainActor func handleIncomingOpenURLIsNoOpWhenSameURLIsAlreadyOpen() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        let initialWatchCallCount = fixture.watcher.startCallCount

        // Opening the same URL via handleIncomingOpenURL must not restart the file watcher
        // or trigger a new document load cycle.
        fixture.store.handleIncomingOpenURL(fixture.primaryFileURL, origin: .manual)

        #expect(fixture.watcher.startCallCount == initialWatchCallCount)
        #expect(fixture.store.sourceMarkdown == "# Initial")
    }

    @Test @MainActor func handleIncomingOpenURLIgnoresNonMarkdownFiles() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let txtURL = fixture.temporaryDirectoryURL.appendingPathComponent("file.txt")
        try "hello".write(to: txtURL, atomically: true, encoding: .utf8)

        fixture.store.handleIncomingOpenURL(txtURL, origin: .manual)

        #expect(!fixture.store.hasOpenDocument)
    }
}

private extension ReaderStoreExternalChangeTests {
    static var sampleChangedRegion: ChangedRegion {
        ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)
    }
}