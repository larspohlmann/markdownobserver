//
//  ReaderSidebarDocumentControllerTests.swift
//  minimarkTests
//

import Foundation
import AppKit
import Observation
import SwiftUI
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
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: session
        ))

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.primaryFileURL.path)
        #expect(harness.controller.selectedReaderStore.activeFolderWatchSession?.folderURL.path == harness.temporaryDirectoryURL.path)
    }

    @Test @MainActor func sidebarControllerBurstOpenDeduplicatesSortsAndReusesInitialDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [
                harness.secondaryFileURL,
                harness.primaryFileURL,
                harness.primaryFileURL
            ],
            origin: .manual
        ))

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.compactMap { $0.readerStore.fileURL?.path } == [
            harness.primaryFileURL.path,
            harness.secondaryFileURL.path
        ])
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.secondaryFileURL.path)
    }

    @Test @MainActor func sidebarControllerFocusingExistingDocumentDoesNotDuplicateEntry() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        harness.controller.focusDocument(at: harness.primaryFileURL)

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.selectedReaderStore.fileURL?.path == harness.primaryFileURL.path)
    }

    @Test @MainActor func sidebarControllerDoesNotKeepBlankDocumentWhenWatchedOpenFails() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let missingFileURL = harness.temporaryDirectoryURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("missing.md")

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [missingFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: ReaderFolderWatchSession(
                folderURL: harness.temporaryDirectoryURL,
                options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
                startedAt: .now
            ),
            slotStrategy: .alwaysAppend
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [missingFileURL],
            origin: .folderWatchAutoOpen,
            folderWatchSession: harness.controller.activeFolderWatchSession,
            slotStrategy: .alwaysAppend
        ))

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

    @Test @MainActor func sidebarControllerManualOpenWithinActiveWatchAdoptsSharedWatchSession() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: .default
        )

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))
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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL, nestedFileURL],
            origin: .manual
        ))

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
                    let securityScopeResolver = SecurityScopeResolver(
                        securityScope: TestSecurityScopeAccess(),
                        settingsStore: settingsStore,
                        requestWatchedFolderReauthorization: { _ in nil }
                    )
                    return ReaderStore(
                        rendering: ReaderRenderingDependencies(
                            renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
                        ),
                        file: ReaderFileDependencies(
                            watcher: TestFileWatcher(), io: ReaderDocumentIOService(), actions: TestReaderFileActions()
                        ),
                        folderWatch: ReaderFolderWatchDependencies(
                            autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                            settler: settler,
                            systemNotifier: TestReaderSystemNotifier()
                        ),
                        settingsStore: settingsStore,
                        securityScopeResolver: securityScopeResolver
                    )
                }()
            },
            makeFolderWatchController: {
                ReaderFolderWatchController(
                    folderWatcher: FolderChangeWatcher(
                        verificationDelay: .milliseconds(20),
                        makeEventSource: { _ in
                            DispatchSourceFolderEventSource(
                                pollingInterval: .milliseconds(50),
                                fallbackPollingInterval: .milliseconds(80)
                            )
                        }
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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: favoriteEntry.resolvedOpenDocumentFileURLs(relativeTo: harness.temporaryDirectoryURL),
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: harness.controller.activeFolderWatchSession,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.compactMap { $0.readerStore.fileURL?.path } == [
            harness.primaryFileURL.path,
            harness.secondaryFileURL.path
        ])
    }

    @Test @MainActor func sidebarControllerMirrorsSelectedStoreProjectionAcrossSelectionChanges() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        let selectedDocument = harness.controller.documents[0]
        let unselectedDocument = harness.controller.documents[1]
        harness.controller.selectDocument(selectedDocument.id)

        // Let the observation tracking tasks start their first withObservationTracking call
        await Task.yield()

        var changeDetected = false
        withObservationTracking {
            _ = harness.controller.rowStates
        } onChange: {
            changeDetected = true
        }

        unselectedDocument.readerStore.handleObservedFileChange()
        try await Task.sleep(for: .milliseconds(50))

        #expect(unselectedDocument.readerStore.lastExternalChangeAt != nil)
        #expect(changeDetected)
    }

    @Test @MainActor func sidebarControllerShowsFileSelectionWhenOverThreshold() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let performanceLimit = ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount
        let fileURLs = (0..<performanceLimit + 1).map { index in
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "bulk-%02d.md", index))
            try? "# File \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
        harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(harness.controller.pendingFileSelectionRequest != nil)
        #expect(harness.controller.pendingFileSelectionRequest?.allFileURLs.count == performanceLimit + 1)
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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

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

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, thirdFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        let keptDocumentIDs = Set(harness.controller.documents.prefix(2).map(\.id))

        harness.controller.closeOtherDocuments(keeping: keptDocumentIDs)

        #expect(harness.controller.documents.count == 2)
        #expect(Set(harness.controller.documents.map(\.id)) == keptDocumentIDs)
        #expect(keptDocumentIDs.contains(harness.controller.selectedDocumentID))
    }

    @Test @MainActor func sidebarControllerCloseAllDocumentsResetsToSingleEmptyDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        harness.controller.closeAllDocuments()

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.documents[0].readerStore.fileURL == nil)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
    }

    @Test @MainActor func sidebarControllerCloseAllDocumentsKeepsActiveFolderWatch() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))
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

        // Simulate the file selection dialog confirm flow via coordinator.
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))

        // The initial empty document should be reused for the first file.
        #expect(harness.controller.documents.count == 2)
        #expect(harness.controller.documents.allSatisfy { $0.readerStore.fileURL != nil })
    }

    @Test @MainActor func selectDocumentWithNewestModificationDateSelectsCorrectDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let olderFileURL = harness.temporaryDirectoryURL.appendingPathComponent("older.md")
        let newerFileURL = harness.temporaryDirectoryURL.appendingPathComponent("newer.md")
        try "# Older".write(to: olderFileURL, atomically: true, encoding: .utf8)
        try "# Newer".write(to: newerFileURL, atomically: true, encoding: .utf8)

        let olderDate = Date(timeIntervalSince1970: 1_000_000)
        let newerDate = Date(timeIntervalSince1970: 2_000_000)
        try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderFileURL.path)
        try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerFileURL.path)

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [olderFileURL, newerFileURL],
            origin: .manual
        ))

        harness.controller.selectDocumentWithNewestModificationDate()

        let selectedStore = harness.controller.selectedReaderStore
        #expect(selectedStore.fileURL?.lastPathComponent == "newer.md")
    }

    @Test @MainActor func sidebarControllerCloseDocumentsRemovesSelectedSubset() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, thirdFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        let documentIDsToClose = Set(harness.controller.documents.prefix(2).map(\.id))
        let expectedRemainingDocumentID = harness.controller.documents[2].id

        harness.controller.closeDocuments(documentIDsToClose)

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.documents[0].id == expectedRemainingDocumentID)
        #expect(harness.controller.selectedDocumentID == expectedRemainingDocumentID)
    }

    @Test @MainActor func sidebarControllerAutoOpens12NewestAndDefersRestForMediumFolder() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let fileCount = 20
        var fileURLs: [URL] = []
        for index in 0..<fileCount {
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "note-%02d.md", index))
            try "# Note \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            let modDate = Date(timeIntervalSince1970: Double(1_000_000 + index * 1000))
            try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
            fileURLs.append(fileURL)
        }
        harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(harness.controller.pendingFileSelectionRequest == nil)
        #expect(harness.controller.documents.count == fileCount)

        let loadedDocs = harness.controller.documents.filter { !$0.readerStore.isDeferredDocument }
        let deferredDocs = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }

        #expect(loadedDocs.count == ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
        #expect(deferredDocs.count == fileCount - ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)

        let loadedFileNames = Set(loadedDocs.compactMap { $0.readerStore.fileURL?.lastPathComponent })
        for index in (fileCount - ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)..<fileCount {
            #expect(loadedFileNames.contains(String(format: "note-%02d.md", index)))
        }

        // Newest file (note-19) should be selected
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "note-19.md")
    }

    @Test @MainActor func materializeNewestDeferredDocumentsLoads12NewestAndSelectsNewest() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        let fileCount = 20
        var fileURLs: [URL] = []
        for index in 0..<fileCount {
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "fav-%02d.md", index))
            try "# Fav \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            let modDate = Date(timeIntervalSince1970: Double(1_000_000 + index * 1000))
            try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
            fileURLs.append(fileURL)
        }

        // Simulate favorite restore: all files deferred via coordinator, then materialize separately.
        // Build a plan that defers all files with no post-materialization.
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: fileURLs,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeSelected
        ))
        // Execute the plan's assignments but override the strategy to skip materialization,
        // since the test explicitly calls materializeNewestDeferredDocuments() below.
        harness.controller.executePlan(FileOpenPlan(
            assignments: plan.assignments,
            origin: plan.origin,
            folderWatchSession: plan.folderWatchSession,
            materializationStrategy: .loadAll
        ))

        // All should be deferred
        #expect(harness.controller.documents.count == fileCount)
        #expect(harness.controller.documents.allSatisfy { $0.readerStore.isDeferredDocument })

        // Now materialize the 12 newest
        harness.controller.materializeNewestDeferredDocuments()

        let loadedDocs = harness.controller.documents.filter { !$0.readerStore.isDeferredDocument }
        let deferredDocs = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }

        #expect(loadedDocs.count == ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
        #expect(deferredDocs.count == fileCount - ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)

        let loadedFileNames = Set(loadedDocs.compactMap { $0.readerStore.fileURL?.lastPathComponent })
        for index in (fileCount - ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)..<fileCount {
            #expect(loadedFileNames.contains(String(format: "fav-%02d.md", index)))
        }

        // Newest file should be selected
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "fav-19.md")
        #expect(!harness.controller.selectedReaderStore.isDeferredDocument)
    }

    @Test @MainActor func sidebarControllerLoadsAllFilesAndSelectsNewestForSmallFolder() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let fileCount = 5
        var fileURLs: [URL] = []
        for index in 0..<fileCount {
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "doc-%02d.md", index))
            try "# Doc \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
            let modDate = Date(timeIntervalSince1970: Double(1_000_000 + index * 1000))
            try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
            fileURLs.append(fileURL)
        }
        harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        #expect(harness.controller.pendingFileSelectionRequest == nil)
        #expect(harness.controller.documents.count == fileCount)

        // All files should be fully loaded (none deferred)
        let deferredDocs = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }
        #expect(deferredDocs.isEmpty)

        for document in harness.controller.documents {
            #expect(!document.readerStore.sourceMarkdown.isEmpty)
        }

        // Newest file (doc-04) should be selected
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "doc-04.md")
    }

    // MARK: - Locked appearance propagation (#152)

    @Test @MainActor func coordinatorPropagatesLockedAppearanceToNewDocuments() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let lockedAppearance = LockedAppearance(readerTheme: .newspaper, baseFontSize: 22, syntaxTheme: .nord)

        // Wire up the coordinator the same way the real app does
        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )
        coordinator.configureStoreCallbacks(
            lockedAppearanceProvider: { lockedAppearance },
            onOpenAdditionalDocument: { _, _, _, _ in }
        )

        // Defer a new file (deferred documents don't render, so needsAppearanceRender stays true)
        let fileCoordinator = FileOpenCoordinator(controller: harness.controller)
        fileCoordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            slotStrategy: .alwaysAppend,
            materializationStrategy: .deferOnly
        ))

        // The newly created document should have the locked appearance applied
        let newDocument = harness.controller.document(for: harness.secondaryFileURL)
        #expect(newDocument != nil)
        #expect(newDocument?.readerStore.needsAppearanceRender == true)
    }

    @Test @MainActor func coordinatorDoesNotApplyAppearanceWhenUnlocked() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        // No locked appearance
        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )
        coordinator.configureStoreCallbacks(
            lockedAppearanceProvider: { nil },
            onOpenAdditionalDocument: { _, _, _, _ in }
        )

        let fileCoordinator = FileOpenCoordinator(controller: harness.controller)
        fileCoordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            slotStrategy: .alwaysAppend,
            materializationStrategy: .deferOnly
        ))

        let newDocument = harness.controller.document(for: harness.secondaryFileURL)
        #expect(newDocument != nil)
        #expect(newDocument?.readerStore.needsAppearanceRender == false)
    }

    // MARK: - Favorite restore newest-file selection (#144)

    @Test @MainActor func favoriteRestoreSelectsNewestDocumentByModificationDate() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        // Create 5 files where the newest by mod date (charlie) is NOT last alphabetically (echo is).
        let filesAndDates: [(name: String, secondsOffset: TimeInterval)] = [
            ("alpha.md", 1000),
            ("bravo.md", 3000),
            ("charlie.md", 5000),  // newest
            ("delta.md", 2000),
            ("echo.md", 4000),
        ]
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        var fileURLs: [URL] = []
        for (name, offset) in filesAndDates {
            let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(name)
            try "# \(name)".write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: baseDate.addingTimeInterval(offset)],
                ofItemAtPath: fileURL.path
            )
            fileURLs.append(fileURL)
        }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        // Open via coordinator with deferThenMaterializeNewest, simulating favorite restore.
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: fileURLs,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeNewest(count: 12)
        ))

        // All 5 files should be loaded (count <= 12 so all get materialized).
        #expect(harness.controller.documents.count == 5)

        // The selected document must be charlie.md (newest by mod date), not echo.md (last alphabetically).
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "charlie.md")
    }

    @Test @MainActor func discoveryOfAlreadyOpenFilesDoesNotOverrideNewestSelection() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let alphaURL = harness.temporaryDirectoryURL.appendingPathComponent("alpha.md")
        let betaURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        let zetaURL = harness.temporaryDirectoryURL.appendingPathComponent("zeta.md")

        try "# Alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(1000)],
            ofItemAtPath: alphaURL.path
        )

        try "# Beta".write(to: betaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(5000)],  // newest
            ofItemAtPath: betaURL.path
        )

        try "# Zeta".write(to: zetaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(3000)],  // middle
            ofItemAtPath: zetaURL.path
        )

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )
        let allURLs = [alphaURL, betaURL, zetaURL]

        // Initial open with deferThenMaterializeNewest.
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: allURLs,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeNewest(count: 12)
        ))
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "beta.md")

        // Simulate discoverNewFilesForFavorite re-processing the same files.
        coordinator.open(FileOpenRequest(
            fileURLs: allURLs,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            slotStrategy: .alwaysAppend,
            materializationStrategy: .deferOnly
        ))

        // Re-select newest after discovery (this is what the fix adds).
        harness.controller.selectDocumentWithNewestModificationDate()

        // beta.md should still be selected (newest by mod date).
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "beta.md")
    }

    @Test @MainActor func discoveryOfNewFilesSelectsNewestOverall() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let alphaURL = harness.temporaryDirectoryURL.appendingPathComponent("alpha.md")
        let betaURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")

        try "# Alpha".write(to: alphaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(1000)],
            ofItemAtPath: alphaURL.path
        )

        try "# Beta".write(to: betaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(3000)],
            ofItemAtPath: betaURL.path
        )

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        // Initial open.
        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [alphaURL, betaURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            materializationStrategy: .deferThenMaterializeNewest(count: 12)
        ))
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "beta.md")

        // A newer file appears (discovered by folder watch).
        let gammaURL = harness.temporaryDirectoryURL.appendingPathComponent("gamma.md")
        try "# Gamma".write(to: gammaURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: baseDate.addingTimeInterval(5000)],  // newest overall
            ofItemAtPath: gammaURL.path
        )

        coordinator.open(FileOpenRequest(
            fileURLs: [gammaURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            slotStrategy: .alwaysAppend,
            materializationStrategy: .deferOnly
        ))

        // Re-select newest after discovery.
        harness.controller.selectDocumentWithNewestModificationDate()

        // gamma.md should now be selected (newest overall).
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "gamma.md")
    }

    @Test @MainActor func liveAutoOpenedFileShowsExternalChangeIndicator() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        harness.folderWatchControllerWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(fileURL: harness.secondaryFileURL, kind: .added)
        ])

        await Task.yield()

        let autoOpenedDoc = harness.controller.documents.first {
            $0.readerStore.fileURL?.lastPathComponent == "zeta.md"
        }
        #expect(autoOpenedDoc != nil)

        let hasIndicator = await waitUntil(timeout: .seconds(2)) {
            guard let autoOpenedDoc else { return false }
            return autoOpenedDoc.readerStore.hasUnacknowledgedExternalChange
        }
        #expect(hasIndicator)

        let pulseObserved = await waitUntil(timeout: .seconds(2)) {
            guard let autoOpenedDoc else { return false }
            return (harness.controller.rowStates[autoOpenedDoc.id]?.indicatorPulseToken ?? 0) >= 1
        }
        #expect(pulseObserved)
    }

    @Test @MainActor func liveAutoOpenedAddedFileTurnsYellowAfterExternalEdit() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        )

        harness.folderWatchControllerWatcher.emitChangedMarkdownEvents([
            ReaderFolderWatchChangeEvent(fileURL: harness.secondaryFileURL, kind: .added)
        ])

        let autoOpenedDoc = try #require(await waitUntil(timeout: .seconds(2)) {
            harness.controller.documents.contains { $0.readerStore.fileURL?.path == harness.secondaryFileURL.path }
        } ? harness.controller.documents.first { $0.readerStore.fileURL?.path == harness.secondaryFileURL.path } : nil)

        _ = await waitUntil(timeout: .seconds(2)) {
            (harness.controller.rowStates[autoOpenedDoc.id]?.indicatorPulseToken ?? 0) >= 1
        }

        let addedRowState = try #require(harness.controller.rowStates[autoOpenedDoc.id])
        #expect(addedRowState.indicatorPulseToken >= 1)
        let addedColor = try #require(NSColor(
            addedRowState.indicatorState.color(
                for: harness.settingsStore.currentSettings,
                colorScheme: .light
            )
        ).usingColorSpace(.deviceRGB))
        let expectedGreen = try #require(NSColor.systemGreen.usingColorSpace(.deviceRGB))

        #expect(abs(addedColor.redComponent - expectedGreen.redComponent) < 0.002)
        #expect(abs(addedColor.greenComponent - expectedGreen.greenComponent) < 0.002)
        #expect(abs(addedColor.blueComponent - expectedGreen.blueComponent) < 0.002)

        try "# Zeta Edited".write(to: harness.secondaryFileURL, atomically: true, encoding: .utf8)

        autoOpenedDoc.readerStore.handleObservedFileChange()

        _ = await waitUntil(timeout: .seconds(2)) {
            harness.controller.rowStates[autoOpenedDoc.id]?.indicatorState.showsIndicator == true
        }

        _ = await waitUntil(timeout: .seconds(2)) {
            (harness.controller.rowStates[autoOpenedDoc.id]?.indicatorPulseToken ?? 0) >= 2
        }

        let editedRowState = try #require(harness.controller.rowStates[autoOpenedDoc.id])
        #expect(editedRowState.indicatorPulseToken >= 2)
        let editedColor = try #require(NSColor(
            editedRowState.indicatorState.color(
                for: harness.settingsStore.currentSettings,
                colorScheme: .light
            )
        ).usingColorSpace(.deviceRGB))
        let expectedYellow = try #require(NSColor.systemYellow.usingColorSpace(.deviceRGB))

        #expect(abs(editedColor.redComponent - expectedYellow.redComponent) < 0.002)
        #expect(abs(editedColor.greenComponent - expectedYellow.greenComponent) < 0.002)
        #expect(abs(editedColor.blueComponent - expectedYellow.blueComponent) < 0.002)
    }

    @Test @MainActor func initialBatchAutoOpenDoesNotSetExternalChangeIndicator() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        harness.folderWatchControllerWatcher.markdownFilesToReturn = [
            harness.primaryFileURL,
            harness.secondaryFileURL
        ]

        try harness.controller.startWatchingFolder(
            folderURL: harness.temporaryDirectoryURL,
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        )

        for document in harness.controller.documents {
            #expect(!document.readerStore.hasUnacknowledgedExternalChange)
        }
    }

    @Test @MainActor func documentExposesNormalizedFileURLAfterOpen() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

        let document = harness.controller.documents.first {
            $0.readerStore.fileURL != nil
        }
        #expect(document != nil)
        #expect(document?.normalizedFileURL == ReaderFileRouting.normalizedFileURL(harness.primaryFileURL))
    }

    @Test @MainActor func documentForURLReturnsNilAfterClosingDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual
        ))

        let primaryDoc = harness.controller.document(for: harness.primaryFileURL)
        #expect(primaryDoc != nil)

        harness.controller.closeDocument(primaryDoc!.id)

        #expect(harness.controller.document(for: harness.primaryFileURL) == nil)
        #expect(harness.controller.document(for: harness.secondaryFileURL) != nil)
    }

    @Test @MainActor func documentForURLFindsDocumentWithNonCanonicalPath() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual
        ))

        // Construct a non-canonical path with a redundant "./" component
        let nonCanonicalURL = harness.temporaryDirectoryURL
            .appendingPathComponent(".")
            .appendingPathComponent("alpha.md")

        #expect(harness.controller.document(for: nonCanonicalURL) != nil)
    }

    // MARK: - Lazy folder-watch controller (#280)

    @Test @MainActor func folderWatchControllerIsNotCreatedUntilNeeded() throws {
        var controllerCreated = false
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.lazy-test.\(UUID().uuidString)"
        )
        let controller = ReaderSidebarDocumentController(
            settingsStore: settingsStore,
            makeReaderStore: {
                let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
                let securityScopeResolver = SecurityScopeResolver(
                    securityScope: TestSecurityScopeAccess(),
                    settingsStore: settingsStore,
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                return ReaderStore(
                    rendering: ReaderRenderingDependencies(
                        renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
                    ),
                    file: ReaderFileDependencies(
                        watcher: TestFileWatcher(), io: ReaderDocumentIOService(), actions: TestReaderFileActions()
                    ),
                    folderWatch: ReaderFolderWatchDependencies(
                        autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
                        settler: settler,
                        systemNotifier: TestReaderSystemNotifier()
                    ),
                    settingsStore: settingsStore,
                    securityScopeResolver: securityScopeResolver
                )
            },
            makeFolderWatchController: {
                controllerCreated = true
                return ReaderFolderWatchController(
                    folderWatcher: TestFolderWatcher(),
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
                )
            }
        )

        #expect(!controllerCreated)
        #expect(controller.activeFolderWatchSession == nil)
        #expect(!controller.isFolderWatchInitialScanInProgress)
        #expect(controller.documents.count == 1)
        _ = controller
    }
}
