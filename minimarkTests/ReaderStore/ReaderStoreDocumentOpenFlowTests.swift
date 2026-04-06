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

        #expect(fixture.store.fileURL != nil)
        #expect(fixture.store.fileDisplayName == "first.md")
        #expect(fixture.store.documentLoadState == .ready)
        #expect(fixture.store.renderedHTMLDocument.contains("Initial"))
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

        #expect(fixture.store.fileDisplayName == "second.md")
        #expect(fixture.store.renderedHTMLDocument.contains("Second"))
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

        #expect(fixture.store.lastError != nil || fixture.store.isCurrentFileMissing)
    }

    @Test @MainActor func openFileRecordsRecentHistory() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        #expect(fixture.settings.recordedRecentManuallyOpenedFiles.count >= 1)
    }
}
