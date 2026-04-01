//
//  ReaderSidebarDocumentControllerTests.swift
//  minimarkTests
//

import Foundation
import Combine
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderSidebarDocumentControllerTests {
    @Test @MainActor func sidebarControllerAutoOpenBurstReusesInitialEmptyDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let folderOptions = ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: folderOptions,
            startedAt: .now
        )
        harness.settingsStore.addRecentWatchedFolder(harness.temporaryDirectoryURL, options: folderOptions)
        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.primaryFileURL.path)
        #expect(harness.controller.selectedReaderStore.activeFolderWatchSession?.folderURL.path == harness.temporaryDirectoryURL.path)
    }

    @Test @MainActor func sidebarControllerBurstOpenDeduplicatesSortsAndReusesInitialDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [
                harness.secondaryFileURL,
                harness.primaryFileURL,
                harness.primaryFileURL
            ],
            origin: .manual
        )

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.compactMap { $0.readerStore.fileURL?.path } == [
            harness.primaryFileURL.path,
            harness.secondaryFileURL.path
        ])
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.secondaryFileURL.path)
    }

    @Test @MainActor func sidebarControllerSelectingExistingDocumentDoesNotDuplicateEntry() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        harness.controller.openDocumentInSelectedSlot(at: harness.primaryFileURL, origin: .manual)

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.primaryFileURL.path)
    }

    @Test @MainActor func sidebarControllerDoesNotKeepBlankDocumentWhenWatchedOpenFails() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let missingFileURL = harness.temporaryDirectoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("missing.md")

        harness.controller.openAdditionalDocument(
            at: missingFileURL,
            origin: .folderWatchAutoOpen,
            folderWatchSession: ReaderFolderWatchSession(
                folderURL: harness.temporaryDirectoryURL,
                options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
                startedAt: .now
            ),
            preferEmptySelection: false
        )

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
    }

    @Test @MainActor func sidebarControllerFailedWatchedOpenKeepsActiveFolderWatchSession() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )
        let stopCallCountBeforeFailedOpen = harness.folderWatchControllerWatcher.stopCallCount

        let missingFileURL = harness.temporaryDirectoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("missing.md")

        harness.controller.openAdditionalDocument(
            at: missingFileURL,
            origin: .folderWatchAutoOpen,
            folderWatchSession: harness.controller.activeFolderWatchSession,
            preferEmptySelection: false
        )

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
        #expect(harness.controller.canStopFolderWatch)
        #expect(harness.controller.activeFolderWatchSession?.folderURL == harness.temporaryDirectoryURL)
        #expect(harness.folderWatchControllerWatcher.stopCallCount == stopCallCountBeforeFailedOpen)
    }

    @Test @MainActor func sidebarControllerSurfacesInitialScanFailureState() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.folderWatchControllerWatcher.markdownFilesError = NSError(
            domain: "ReaderSidebarDocumentControllerTests",
            code: 91
        )

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders
            )
        )

        #expect(harness.controller.isFolderWatchInitialScanInProgress)
        #expect(await waitUntil(timeout: .seconds(2)) {
            harness.controller.didFolderWatchInitialScanFail && !harness.controller.isFolderWatchInitialScanInProgress
        })
    }

    @Test @MainActor func sidebarControllerStopsActiveFolderWatch() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )

        #expect(harness.controller.canStopFolderWatch)

        harness.controller.stopFolderWatch()

        #expect(!harness.controller.canStopFolderWatch)
        #expect(harness.controller.activeFolderWatchSession == nil)
        #expect(harness.folderWatchControllerWatcher.stopCallCount >= 1)
    }

    @Test @MainActor func sidebarControllerManualOpenWithinActiveWatchAdoptsSharedWatchSession() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )

        harness.controller.openDocumentInSelectedSlot(
            at: harness.primaryFileURL,
            origin: .manual
        )

        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.primaryFileURL.path)
        #expect(harness.controller.selectedReaderStore.activeFolderWatchSession?.folderURL.path == harness.temporaryDirectoryURL.path)
    }

    @Test @MainActor func sidebarControllerWatchedOpenDocumentsRetainDedicatedFileWatchers() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )
        harness.controller.selectDocument(harness.controller.documents[0].id)

        #expect(harness.controller.documents.count == 2)
        #expect(harness.fileWatchers.prefix(2).allSatisfy { $0.startCallCount == 1 })
    }

    @Test @MainActor func sidebarControllerWatchedDocumentIDsTrackActiveSessionScope() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let nestedDirectoryURL = harness.temporaryDirectoryURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("nested.md")
        try "# Nested".write(to: nestedFileURL, atomically: true, encoding: .utf8)

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL, nestedFileURL],
            origin: .manual
        )

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

                let topLevelDocumentIDs: Set<UUID> = Set(harness.controller.documents.compactMap { document in
            guard let fileURL = document.readerStore.fileURL,
                  fileURL.deletingLastPathComponent().path == harness.temporaryDirectoryURL.path else {
                return nil
            }

            return document.id
        })
        #expect(harness.controller.watchedDocumentIDs() == topLevelDocumentIDs)

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        )

        #expect(harness.controller.watchedDocumentIDs() == Set(harness.controller.documents.map(\.id)))
    }

    @Test @MainActor func sidebarControllerWatchChangesOnlyWithIncludedSubfoldersDoesNotCreateInitialDocuments() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-sidebar-real-watch-\(UUID().uuidString)", isDirectory: true)
        let nestedDirectoryURL = directoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.sidebar.real-watch.\(UUID().uuidString)"
        )
        let controller = ReaderSidebarDocumentController(
            settingsStore: settingsStore,
            makeReaderStore: {
                {
                    let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
                    return ReaderStore(
                        renderer: TestMarkdownRenderer(),
                        differ: TestChangedRegionDiffer(),
                        fileWatcher: TestFileWatcher(),
                        folderWatcher: TestFolderWatcher(),
                        settingsStore: settingsStore,
                        securityScope: TestSecurityScopeAccess(),
                        fileActions: TestReaderFileActions(),
                        systemNotifier: TestReaderSystemNotifier(),
                        folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                        settler: settler
                    )
                }()
            },
            makeFolderWatchController: {
                ReaderFolderWatchController(
                    folderWatcher: FolderChangeWatcher(
                        pollingInterval: .milliseconds(50),
                        fallbackPollingInterval: .milliseconds(80),
                        verificationDelay: .milliseconds(20)
                    ),
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
                )
            }
        )

        let topLevelFileURL = directoryURL.appendingPathComponent("top-level.md")
        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("existing.md")
        try "# Top Level".write(to: topLevelFileURL, atomically: false, encoding: .utf8)
        try "# Nested".write(to: nestedFileURL, atomically: false, encoding: .utf8)

        try controller.startWatchingFolder(
            folderURL: directoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders)
        )

        try? await Task.sleep(for: .milliseconds(300))

        #expect(controller.documents.count == 1)
        #expect(controller.selectedReaderStore.fileURL == nil)
    }

    @Test @MainActor func sidebarControllerRestoresFavoriteSavedOpenDocuments() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let nestedDirectoryURL = harness.temporaryDirectoryURL.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectoryURL, withIntermediateDirectories: true)
        let nestedFileURL = nestedDirectoryURL.appendingPathComponent("nested.md")
        try "# Nested".write(to: nestedFileURL, atomically: true, encoding: .utf8)

        let favoriteEntry = ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            openDocumentFileURLs: [
                harness.primaryFileURL,
                harness.secondaryFileURL,
                nestedFileURL
            ]
        )

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: favoriteEntry.options
        )

        harness.controller.openDocumentsBurst(
            at: favoriteEntry.resolvedOpenDocumentFileURLs(relativeTo: harness.temporaryDirectoryURL),
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: harness.controller.activeFolderWatchSession,
            preferEmptySelection: true
        )

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.compactMap { $0.readerStore.fileURL?.path } == [
            harness.primaryFileURL.path,
            harness.secondaryFileURL.path
        ])
    }

    @Test @MainActor func sidebarControllerMirrorsSelectedStoreProjectionAcrossSelectionChanges() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        let primaryDocument = harness.controller.documents[0]
        let secondaryDocument = harness.controller.documents[1]

        harness.controller.selectDocument(primaryDocument.id)
        await Task.yield()
        #expect(harness.controller.selectedFileURL?.path == harness.primaryFileURL.path)
        #expect(harness.controller.selectedWindowTitle == primaryDocument.readerStore.windowTitle)

        harness.controller.selectDocument(secondaryDocument.id)
        await Task.yield()
        #expect(harness.controller.selectedFileURL?.path == harness.secondaryFileURL.path)
        #expect(harness.controller.selectedWindowTitle == secondaryDocument.readerStore.windowTitle)
    }

    @Test @MainActor func sidebarControllerPublishesWhenUnselectedDocumentChanges() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        let selectedDocument = harness.controller.documents[0]
        let unselectedDocument = harness.controller.documents[1]
        harness.controller.selectDocument(selectedDocument.id)

        var changeCount = 0
        let cancellable = harness.controller.objectWillChange.sink {
            changeCount += 1
        }
        defer { cancellable.cancel() }

        unselectedDocument.readerStore.handleObservedFileChange()
        await Task.yield()

        #expect(unselectedDocument.readerStore.lastExternalChangeAt != nil)
        #expect(changeCount > 0)
    }

    @Test @MainActor func sidebarControllerShowsFileSelectionWhenOverThreshold() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )
        harness.controller.selectDocument(harness.controller.documents[0].id)

        let autoOpenLimit = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
        let fileURLs = (0...autoOpenLimit).map { index in
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "bulk-%02d.md", index))
            try? "# File \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
        harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        // When file count exceeds threshold, a file selection request is published instead of auto-opening.
        #expect(harness.controller.pendingFileSelectionRequest != nil)
        #expect(harness.controller.pendingFileSelectionRequest?.allFileURLs.count == autoOpenLimit + 1)
        #expect(harness.controller.selectedFolderWatchAutoOpenWarning == nil)
    }

    @Test @MainActor func sidebarControllerCanSkipInitialAutoOpenPromptForFavoriteRestore() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let autoOpenLimit = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
        let fileURLs = (0...autoOpenLimit).map { index in
            harness.temporaryDirectoryURL.appendingPathComponent(String(format: "bulk-%02d.md", index))
        }
        harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            performInitialAutoOpen: false
        )

        #expect(harness.controller.pendingFileSelectionRequest == nil)
        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
    }

    @Test @MainActor func sidebarControllerLiveBurstDoesNotPublishWarningForOmittedFiles() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL],
            origin: .manual
        )

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        let autoOpenLimit = ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount
        let fileURLs = (0..<(autoOpenLimit + 2)).map { index in
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "live-%02d.md", index))
            try? "# File \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        harness.folderWatchControllerWatcher.emitChangedMarkdownEvents(
            fileURLs.map { ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added) }
        )

        await Task.yield()

        #expect(harness.controller.documents.count == autoOpenLimit + 1)
        #expect(harness.controller.selectedFolderWatchAutoOpenWarning == nil)
    }

    @Test @MainActor func sidebarControllerCloseOtherDocumentsKeepsRequestedDocumentOnly() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        let keptDocumentID = harness.controller.documents[1].id
        harness.controller.closeOtherDocuments(keeping: keptDocumentID)

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.documents[0].id == keptDocumentID)
        #expect(harness.controller.selectedDocumentID == keptDocumentID)
    }

    @Test @MainActor func sidebarControllerCloseOtherDocumentsKeepsRequestedSubset() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, thirdFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        let keptDocumentIDs = Set(harness.controller.documents.prefix(2).map(\.id))

        harness.controller.closeOtherDocuments(keeping: keptDocumentIDs)

        #expect(harness.controller.documents.count == 2)
        #expect(Set(harness.controller.documents.map(\.id)) == keptDocumentIDs)
        #expect(keptDocumentIDs.contains(harness.controller.selectedDocumentID))
    }

    @Test @MainActor func sidebarControllerCloseAllDocumentsResetsToSingleEmptyDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        harness.controller.closeAllDocuments()

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.documents[0].readerStore.fileURL == nil)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
    }

    @Test @MainActor func sidebarControllerCloseAllDocumentsKeepsActiveFolderWatch() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        )
        harness.controller.selectDocument(harness.controller.documents[0].id)

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )

        let watcher = harness.folderWatchControllerWatcher
        let stopCallCountBeforeCloseAll = watcher.stopCallCount

        harness.controller.closeAllDocuments()

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
        #expect(harness.controller.canStopFolderWatch)
        #expect(harness.controller.activeFolderWatchSession?.folderURL == harness.temporaryDirectoryURL)
        #expect(watcher.stopCallCount == stopCallCountBeforeCloseAll)
    }

    @Test @MainActor func sidebarControllerClosingSelectedSubsetKeepsSharedFolderWatchActive() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)
        harness.folderWatchControllerWatcher.markdownFilesToReturn = [
            harness.primaryFileURL,
            harness.secondaryFileURL,
            thirdFileURL
        ]

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        let documentIDsToClose = Set(harness.controller.documents.prefix(2).map(\.id))
        let remainingDocumentID = harness.controller.documents[2].id

        harness.controller.closeDocuments(documentIDsToClose)

        #expect(harness.controller.canStopFolderWatch)
        #expect(harness.controller.activeFolderWatchSession?.folderURL == harness.temporaryDirectoryURL)
        #expect(harness.controller.documents.map(\.id) == [remainingDocumentID])
    }

    @Test @MainActor func sidebarControllerIncludeSubfoldersAutoOpenOpensFilesAsynchronously() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let subfolderURL = harness.temporaryDirectoryURL.appendingPathComponent("subfolder", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
        let subfolderFileURL = subfolderURL.appendingPathComponent("nested.md")
        try "# Nested".write(to: subfolderFileURL, atomically: true, encoding: .utf8)

        harness.folderWatchControllerWatcher.markdownFilesToReturn = [
            harness.primaryFileURL,
            harness.secondaryFileURL,
            subfolderFileURL
        ]

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders)
        )

        // The includeSubfolders path runs the scan asynchronously.
        #expect(harness.controller.isFolderWatchInitialScanInProgress)

        #expect(await waitUntil(timeout: .seconds(2)) {
            !harness.controller.isFolderWatchInitialScanInProgress
        })

        #expect(harness.controller.documents.count == 3)
        let openFileURLPaths = Set(harness.controller.documents.compactMap { $0.readerStore.fileURL?.path })
        #expect(openFileURLPaths.contains(harness.primaryFileURL.path))
        #expect(openFileURLPaths.contains(harness.secondaryFileURL.path))
        #expect(openFileURLPaths.contains(subfolderFileURL.path))
        #expect(!harness.controller.didFolderWatchInitialScanFail)
    }

    @Test @MainActor func sidebarControllerFileSelectionBurstReusesInitialEmptyDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders),
            startedAt: .now
        )

        // Simulate the file selection dialog confirm flow: open files with preferEmptySelection true.
        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        // The initial empty document should be reused for the first file.
        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.allSatisfy { $0.readerStore.fileURL != nil })
    }

    @Test @MainActor func sidebarControllerCloseDocumentsRemovesSelectedSubset() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, thirdFileURL, harness.secondaryFileURL],
            origin: .manual
        )

        let documentIDsToClose = Set(harness.controller.documents.prefix(2).map(\.id))
        let expectedRemainingDocumentID = harness.controller.documents[2].id

        harness.controller.closeDocuments(documentIDsToClose)

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.documents[0].id == expectedRemainingDocumentID)
        #expect(harness.controller.selectedDocumentID == expectedRemainingDocumentID)
    }
}