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

        fixture.store.opener.open(at: fixture.primaryFileURL)

        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.store.externalChange.lastExternalChangeAt != nil)
    }

    @Test @MainActor func statusBarTimestampUsesFilesystemModificationTimeAndPrefersExternalChangeTime() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        #expect(fixture.store.statusBarTimestamp == nil)

        fixture.store.opener.open(at: fixture.primaryFileURL)

        #expect(fixture.store.statusBarTimestamp == .lastModified(fixture.store.document.fileLastModifiedAt!))

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.statusBarTimestamp == .updated(fixture.store.externalChange.lastExternalChangeAt!))
    }

    @Test @MainActor func handleObservedFileChangePostsSystemNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.notifier.fileChangeNotifications == [
            TestReaderSystemNotifier.FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .modified,
                watchedFolderURL: nil
            )
        ])
    }

    @Test @MainActor func handleObservedFileChangePostsDeletedNotificationWhenFileMissing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.delete(fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.notifier.fileChangeNotifications == [
            TestReaderSystemNotifier.FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .deleted,
                watchedFolderURL: nil
            )
        ])
    }

    @Test @MainActor func folderWatchAutoOpenPostsAddedNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = FolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())
        fixture.store.folderWatchDispatcher.setSession(session)

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.notifier.fileChangeNotifications == [
            TestReaderSystemNotifier.FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .added,
                watchedFolderURL: FileRouting.normalizedFileURL(folderURL)
            )
        ])
    }

    @Test @MainActor func folderWatchAutoOpenPostsModifiedNotificationWhenBaselineProvided() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = FolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())
        fixture.store.folderWatchDispatcher.setSession(session)

        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Old content"
        )

        #expect(fixture.notifier.fileChangeNotifications == [
            TestReaderSystemNotifier.FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .modified,
                watchedFolderURL: FileRouting.normalizedFileURL(folderURL)
            )
        ])
    }

    @Test @MainActor func handleObservedFileChangePostsModifiedNotificationWithWatchedFolderURL() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderURL = fixture.temporaryDirectoryURL
        let options = FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = FolderWatchSession(folderURL: folderURL, options: options, startedAt: Date())
        fixture.store.folderWatchDispatcher.setSession(session)

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.notifier.fileChangeNotifications == [
            TestReaderSystemNotifier.FileChangeNotification(
                fileURL: FileRouting.normalizedFileURL(fixture.primaryFileURL),
                changeKind: .modified,
                watchedFolderURL: FileRouting.normalizedFileURL(folderURL)
            )
        ])
    }

    @Test @MainActor func handleObservedFileChangeSkipsSystemNotificationWhenDisabled() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            notificationsEnabled: false
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.notifier.fileChangeNotifications.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenSkipsSystemNotificationWhenDisabled() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            notificationsEnabled: false
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.notifier.fileChangeNotifications.isEmpty)
    }

    @Test @MainActor func decoratedWindowTitlePrependsAsteriskOnlyWhenPending() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)

        #expect(fixture.store.decoratedWindowTitle == "\(fixture.store.document.windowTitle)")
        #expect(!fixture.store.decoratedWindowTitle.hasPrefix("* "))

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.decoratedWindowTitle == "* \(fixture.store.document.windowTitle)")
    }

    @Test @MainActor func readerStoreKeepsDocumentViewModeInPreviewWithoutOpenDocument() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)

        fixture.store.sourceEditingController.setViewMode(.split, hasOpenDocument: fixture.store.document.hasOpenDocument)

        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCanSwitchToSourceAndResetsToPreviewForNewFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.sourceEditingController.setViewMode(.source, hasOpenDocument: fixture.store.document.hasOpenDocument)

        #expect(fixture.store.sourceEditingController.documentViewMode == .source)

        fixture.store.opener.open(at: fixture.secondaryFileURL)

        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCanSwitchToSplitAndResetsToPreviewForNewFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.sourceEditingController.setViewMode(.split, hasOpenDocument: fixture.store.document.hasOpenDocument)

        #expect(fixture.store.sourceEditingController.documentViewMode == .split)

        fixture.store.opener.open(at: fixture.secondaryFileURL)

        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)
    }

    @Test @MainActor func readerStoreCyclesDocumentViewModesInPreviewSplitSourceOrder() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)

        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)

        fixture.store.sourceEditingController.toggleViewMode()
        #expect(fixture.store.sourceEditingController.documentViewMode == .split)

        fixture.store.sourceEditingController.toggleViewMode()
        #expect(fixture.store.sourceEditingController.documentViewMode == .source)

        fixture.store.sourceEditingController.toggleViewMode()
        #expect(fixture.store.sourceEditingController.documentViewMode == .preview)
    }

    @Test @MainActor func manualReloadCurrentFileClearsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)

        fixture.write(content: "# Updated", to: fixture.primaryFileURL)
        fixture.store.reloader.reloadCurrentFile(forceHighlight: true, acknowledgeExternalChange: true)

        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func autoRefreshEnabledReloadsContentButKeepsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.sourceMarkdown == "# Modified")
        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func externalDeletionMarksOpenDocumentAsMissingEvenWhenAutoRefreshIsDisabled() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let originalMarkdown = fixture.store.document.sourceMarkdown
        let originalHTML = fixture.store.renderingController.renderedHTMLDocument
        fixture.delete(fixture.primaryFileURL)

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.isCurrentFileMissing)
        #expect(fixture.store.document.fileURL == FileRouting.normalizedFileURL(fixture.primaryFileURL))
        #expect(fixture.store.document.sourceMarkdown == originalMarkdown)
        #expect(fixture.store.renderingController.renderedHTMLDocument == originalHTML)
        #expect(fixture.store.document.lastError?.message.contains("Failed to read file") == true)
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func recreatedMissingDocumentClearsMissingStateOnNextObservedChange() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.delete(fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.isCurrentFileMissing)

        fixture.write(content: "# Restored", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(!fixture.store.document.isCurrentFileMissing)
        #expect(fixture.store.document.sourceMarkdown == "# Restored")
    }

    @Test @MainActor func folderWatchAutoOpenIgnoresInitialWatcherNoiseWhenContentIsUnchanged() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)
        #expect(fixture.store.document.changedRegions.isEmpty)

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.sourceMarkdown == "# Initial")
        #expect(fixture.store.document.changedRegions.isEmpty)
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.store.externalChange.lastExternalChangeAt == nil)
    }

    @Test @MainActor func folderWatchAutoOpenAddedFileDoesNotHighlightItsInitialSettlingWrite() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions.isEmpty)
        #expect(fixture.store.document.sourceMarkdown == "# Updated Once")
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchModifiedFileAutoOpenShowsChangedRegionsImmediately() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)

        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Initial"
        )

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.document.sourceMarkdown == "# Updated Once")
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenWithoutOwnedWatchDoesNotPostDuplicateSystemNotification() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.notifier.fileChangeNotifications.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenStillHighlightsAfterIgnoredInitialWatcherNoise() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.store.externalChangeHandler.handleObservedFileChange()
        #expect(fixture.store.document.changedRegions.isEmpty)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")

        fixture.write(content: "# Updated Again", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.document.sourceMarkdown == "# Updated Again")
    }

    @Test @MainActor func folderWatchModifiedFileAutoOpenStillHighlightsLaterExternalRefresh() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.write(content: "# Updated Once", to: fixture.primaryFileURL)
        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Initial"
        )

        fixture.store.externalChangeHandler.handleObservedFileChange()
        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])

        fixture.write(content: "# Updated Twice", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.document.sourceMarkdown == "# Updated Twice")
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenAddedFileAbsorbsInitialChangedContentWithoutIndicators() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        fixture.write(content: "# Settled Initial Content", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions.isEmpty)
        #expect(fixture.store.document.sourceMarkdown == "# Settled Initial Content")
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)

        fixture.write(content: "# Real Follow Up Change", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.document.sourceMarkdown == "# Real Follow Up Change")
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenRecoversContentWhenInitialSettlingWriteMissesWatcherEvent() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion],
            autoOpenSettlingInterval: 0.4
        )
        defer { fixture.cleanup() }

        fixture.write(content: "", to: fixture.primaryFileURL)

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)
        #expect(fixture.store.document.sourceMarkdown.isEmpty)
        #expect(fixture.store.document.documentLoadState == .settlingAutoOpen)

        fixture.write(content: "# Settled Initial Content", to: fixture.primaryFileURL)

        let settled = await waitUntil(timeout: .seconds(1)) {
            fixture.store.document.sourceMarkdown == "# Settled Initial Content"
        }

        #expect(settled)
        #expect(fixture.store.document.changedRegions.isEmpty)
        #expect(fixture.store.document.documentLoadState == .ready)
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func folderWatchAutoOpenEmptyFileKeepsSettlingStateUntilContentArrives() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            autoOpenSettlingInterval: 0.02
        )
        defer { fixture.cleanup() }

        fixture.write(content: "", to: fixture.primaryFileURL)

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        #expect(fixture.store.document.documentLoadState == .settlingAutoOpen)

        try? await Task.sleep(for: .milliseconds(60))

        #expect(fixture.store.document.documentLoadState == .settlingAutoOpen)
        #expect(fixture.store.document.sourceMarkdown.isEmpty)

        fixture.write(content: "# Arrived Later", to: fixture.primaryFileURL)

        let settled = await waitUntil(timeout: .seconds(1)) {
            fixture.store.document.documentLoadState == .ready && fixture.store.document.sourceMarkdown == "# Arrived Later"
        }

        #expect(settled)
        #expect(fixture.store.document.changedRegions.isEmpty)
    }

    @Test @MainActor func folderWatchAutoOpenedAddedFileHighlightsExternalRefreshAfterSettlingWindowExpires() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion],
            autoOpenSettlingInterval: 0.01
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .folderWatchAutoOpen)

        try? await Task.sleep(for: .milliseconds(30))

        fixture.write(content: "# Later External Change", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.document.sourceMarkdown == "# Later External Change")
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func manualOpenStillHighlightsOnFirstExternalRefresh() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL, origin: .manual)

        #expect(fixture.store.document.documentLoadState == .ready)

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
    }

        @Test @MainActor func manualOpenWithinWatchedFolderUsesFolderScopeWithoutRetryingChildFileScope() throws {
            let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
            defer { fixture.cleanup() }
            let normalizedPrimaryFilePath = FileRouting.normalizedFileURL(fixture.primaryFileURL).path

            let options = FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
            let session = FolderWatchSession(
                folderURL: fixture.temporaryDirectoryURL,
                options: options,
                startedAt: .now
            )
            fixture.settings.addRecentWatchedFolder(fixture.temporaryDirectoryURL, options: options)
            fixture.securityScope.didStartAccessResponsesByPath[fixture.primaryFileURL.path] = [false]
            fixture.securityScope.didStartAccessResponsesByPath[normalizedPrimaryFilePath] = [false]

            fixture.store.opener.open(
                at: fixture.primaryFileURL,
                origin: .manual,
                folderWatchSession: session
            )

            #expect(fixture.store.document.sourceMarkdown == "# Initial")
            #expect(
                fixture.securityScope.accessedURLs.map(FileRouting.normalizedFileURL) == [
                    FileRouting.normalizedFileURL(fixture.primaryFileURL),
                    FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL)
                ]
            )
        }

    @Test @MainActor func openingFileClearsPendingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)

        fixture.store.opener.open(at: fixture.secondaryFileURL)

        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(!fixture.store.decoratedWindowTitle.hasPrefix("* "))
    }

    @Test @MainActor func openingSecondFileStopsPreviousWatcherBeforeRebinding() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.opener.open(at: fixture.secondaryFileURL)

        #expect(fixture.watcher.operations == [
            .stop,
            .start(FileRouting.normalizedFileURL(fixture.primaryFileURL)),
            .stop,
            .start(FileRouting.normalizedFileURL(fixture.secondaryFileURL))
        ])
    }

    @Test @MainActor func failedOpenPreservesCurrentFileWatcherAndAvoidsDuplicateRebinds() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let initialStartCallCount = fixture.watcher.startCallCount
        let initialStopCallCount = fixture.watcher.stopCallCount

        let missingFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("missing.md")
        fixture.store.opener.open(at: missingFileURL)
        fixture.store.opener.open(at: missingFileURL)

        #expect(fixture.store.document.fileURL == FileRouting.normalizedFileURL(fixture.primaryFileURL))
        #expect(fixture.watcher.startCallCount == initialStartCallCount)
        #expect(fixture.watcher.stopCallCount == initialStopCallCount)
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)

        fixture.watcher.emitChange()
        await Task.yield()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.fileChangeNotifications.count == 1)
    }

    @Test @MainActor func autoRefreshDisabledStillMarksExternalChangeAsPending() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")

        fixture.write(content: "# Modified", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
    }

    @Test @MainActor func currentWatchedFileRetainsDedicatedFileWatcherOwnership() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: .default,
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: session
        )

        #expect(fixture.watcher.startCallCount == 1)
        #expect(fixture.watcher.lastStartedFileURL == FileRouting.normalizedFileURL(fixture.primaryFileURL))
    }

    @Test @MainActor func watchedFolderEventForCurrentFileDoesNotTriggerExternalChangeWhenFileWatcherOwnsCurrentFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: .default,
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)
        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: session
        )

        fixture.store.folderWatchInput.handleObservedWatchedFolderChanges([
            FolderWatchChangeEvent(
                fileURL: fixture.primaryFileURL,
                kind: .modified,
                previousMarkdown: "# Initial"
            )
        ])

        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.fileChangeNotifications.isEmpty)
        #expect(fixture.watcher.startCallCount == 1)
    }

    @Test @MainActor func fileWatcherEventForWatchedCurrentFileTriggersExternalChange() async throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: .default,
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)
        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .manual,
            folderWatchSession: session
        )

        fixture.watcher.emitChange()
        await Task.yield()

        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.notifier.fileChangeNotifications.count == 1)
    }

    @Test @MainActor func watchedFolderChangesOpenMarkdownAsAdditionalDocuments() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        let fourthFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("fourth.md")
        fixture.write(content: "# Fourth", to: fourthFileURL)
        let unsupportedURL = fixture.temporaryDirectoryURL.appendingPathComponent("skip.txt")
        fixture.write(content: "ignore", to: unsupportedURL)

        var openedAdditionalDocuments: [URL] = []
        var openedEvents: [FolderWatchChangeEvent] = []
        fixture.store.folderWatchDispatcher.setAdditionalOpenHandler { event, _, _ in
            openedAdditionalDocuments.append(FileRouting.normalizedFileURL(event.fileURL))
            openedEvents.append(event)
        }

        fixture.store.folderWatchInput.handleObservedWatchedFolderChanges([
            FolderWatchChangeEvent(fileURL: fixture.primaryFileURL, kind: .modified, previousMarkdown: "# Initial"),
            FolderWatchChangeEvent(fileURL: fourthFileURL, kind: .added),
            FolderWatchChangeEvent(fileURL: unsupportedURL, kind: .added)
        ])

        #expect(openedAdditionalDocuments == [FileRouting.normalizedFileURL(fourthFileURL)])
        #expect(openedEvents[0].kind == .added)
        #expect(openedEvents[0].previousMarkdown == nil)
        #expect(fixture.store.folderWatchDispatcher.lastWatchedFolderEventAt != nil)
    }

    @Test @MainActor func watchedFolderAddedFilesOpenAsAdditionalDocumentsEvenWhenWatcherOwnerHasNoOpenDocument() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        let createdFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("created.md")
        fixture.write(content: "", to: createdFileURL)

        var openedEvents: [FolderWatchChangeEvent] = []
        fixture.store.folderWatchDispatcher.setAdditionalOpenHandler { event, _, _ in
            openedEvents.append(event)
        }

        fixture.store.folderWatchInput.handleObservedWatchedFolderChanges([
            FolderWatchChangeEvent(fileURL: createdFileURL, kind: .added)
        ])

        #expect(fixture.store.document.fileURL == nil)
        #expect(openedEvents.map(\.fileURL) == [FileRouting.normalizedFileURL(createdFileURL)])
        #expect(openedEvents.map(\.kind) == [.added])
        #expect(fixture.store.folderWatchDispatcher.lastWatchedFolderEventAt != nil)
    }

    @Test @MainActor func watchedFolderModifiedFilesForwardPreviousMarkdownToAdditionalDocumentCallback() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        let changedFileURL = fixture.secondaryFileURL
        var capturedEvent: FolderWatchChangeEvent?
        fixture.store.folderWatchDispatcher.setAdditionalOpenHandler { event, _, _ in
            capturedEvent = event
        }

        fixture.store.folderWatchInput.handleObservedWatchedFolderChanges([
            FolderWatchChangeEvent(
                fileURL: changedFileURL,
                kind: .modified,
                previousMarkdown: "# Second"
            )
        ])

        #expect(capturedEvent?.fileURL == FileRouting.normalizedFileURL(changedFileURL))
        #expect(capturedEvent?.kind == .modified)
        #expect(capturedEvent?.previousMarkdown == "# Second")
    }

    @Test @MainActor func watchedFolderLiveBurstPublishesWarningForOmittedFiles() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let session = FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        let autoOpenLimit = FolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount
        let fileURLs = (0..<(autoOpenLimit + 2)).map { index in
            let fileURL = fixture.temporaryDirectoryURL.appendingPathComponent(String(format: "live-%02d.md", index))
            fixture.write(content: "# File \(index)", to: fileURL)
            return fileURL
        }

        var openedAdditionalDocuments: [URL] = []
        fixture.store.folderWatchDispatcher.setAdditionalOpenHandler { event, _, _ in
            openedAdditionalDocuments.append(FileRouting.normalizedFileURL(event.fileURL))
        }

        fixture.store.folderWatchInput.handleObservedWatchedFolderChanges(
            fileURLs.map { FolderWatchChangeEvent(fileURL: $0, kind: .added) }
        )

        #expect(openedAdditionalDocuments == Array(fileURLs.prefix(autoOpenLimit)).map(FileRouting.normalizedFileURL))
        #expect(fixture.store.folderWatchDispatcher.autoOpenWarning?.autoOpenedFileCount == autoOpenLimit)
        #expect(fixture.store.folderWatchDispatcher.autoOpenWarning?.folderURL == FileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.store.folderWatchDispatcher.autoOpenWarning?.omittedFileURLs == Array(fileURLs.dropFirst(autoOpenLimit)).map(FileRouting.normalizedFileURL))
    }

}

// MARK: - handleIncomingOpenURL deduplication

extension ReaderStoreExternalChangeTests {
    @Test @MainActor func handleIncomingOpenURLIsNoOpWhenSameURLIsAlreadyOpen() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        let initialWatchCallCount = fixture.watcher.startCallCount

        // Opening the same URL via handleIncomingOpenURL must not restart the file watcher
        // or trigger a new document load cycle.
        fixture.store.opener.handleIncomingURL(fixture.primaryFileURL, origin: .manual)

        #expect(fixture.watcher.startCallCount == initialWatchCallCount)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
    }

    @Test @MainActor func handleIncomingOpenURLIgnoresNonMarkdownFiles() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let txtURL = fixture.temporaryDirectoryURL.appendingPathComponent("file.txt")
        try "hello".write(to: txtURL, atomically: true, encoding: .utf8)

        fixture.store.opener.handleIncomingURL(txtURL, origin: .manual)

        #expect(!fixture.store.document.hasOpenDocument)
    }
}

private extension ReaderStoreExternalChangeTests {
    static var sampleChangedRegion: ChangedRegion {
        ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)
    }
}