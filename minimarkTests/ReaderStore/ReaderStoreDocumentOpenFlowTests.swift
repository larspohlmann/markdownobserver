//
//  ReaderStoreDocumentOpenFlowTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreDocumentOpenFlowTests {

    // MARK: - openFile

    @Test @MainActor func openFileSetsDocumentState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.store.document.fileURL != nil)
        #expect(fixture.store.document.fileDisplayName == "first.md")
        #expect(fixture.store.document.documentLoadState == .ready)
        #expect(fixture.store.renderingController.renderedHTMLDocument.contains("Initial"))
    }

    @Test @MainActor func openFileStartsFileWatcher() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.watcher.startCallCount == 1)
    }

    @Test @MainActor func openFileClearsExistingDocumentState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.openFile(at: fixture.secondaryFileURL)

        #expect(fixture.store.document.fileDisplayName == "second.md")
        #expect(fixture.store.renderingController.renderedHTMLDocument.contains("Second"))
    }

    @Test @MainActor func handleIncomingOpenURLDeduplicatesCurrentFile() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        let watcherStartCountAfterOpen = fixture.watcher.startCallCount

        fixture.store.handleIncomingOpenURL(fixture.primaryFileURL, origin: .manual)

        #expect(fixture.watcher.startCallCount == watcherStartCountAfterOpen)
    }

    @Test @MainActor func openFileForMissingFileSetsErrorOrMissingState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let missingFileURL = fixture.temporaryDirectoryURL.appendingPathComponent("nonexistent.md")
        fixture.store.openFile(at: missingFileURL)

        #expect(fixture.store.document.lastError != nil || fixture.store.document.isCurrentFileMissing)
    }

    @Test @MainActor func openFileRecordsRecentHistory() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.settings.recordedRecentManuallyOpenedFiles.count >= 1)
    }
}
