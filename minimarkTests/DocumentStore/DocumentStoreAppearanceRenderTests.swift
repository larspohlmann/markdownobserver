//
//  DocumentStoreAppearanceRenderTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct DocumentStoreAppearanceRenderTests {
    private let testAppearance = LockedAppearance(readerTheme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)

    @Test @MainActor func setAppearanceOverrideSetsNeedsAppearanceRender() throws {
        let fixture = try DocumentStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        #expect(!fixture.store.renderingController.needsAppearanceRender)

        fixture.store.renderingController.setAppearanceOverride(testAppearance)

        #expect(fixture.store.renderingController.needsAppearanceRender)
    }

    @Test @MainActor func renderWithAppearanceClearsNeedsAppearanceRender() throws {
        let fixture = try DocumentStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)

        fixture.store.renderingController.setAppearanceOverride(testAppearance)
        #expect(fixture.store.renderingController.needsAppearanceRender)

        try fixture.store.renderingController.renderWithAppearance(
            testAppearance,
            sourceMarkdown: fixture.store.document.sourceMarkdown,
            changedRegions: fixture.store.document.changedRegions,
            unsavedChangedRegions: fixture.store.sourceEditingController.unsavedChangedRegions,
            fileURL: fixture.store.document.fileURL,
            folderWatchSession: fixture.store.folderWatchDispatcher.activeFolderWatchSession
        )

        #expect(!fixture.store.renderingController.needsAppearanceRender)
    }

    @Test @MainActor func renderCurrentMarkdownClearsNeedsAppearanceRender() throws {
        let fixture = try DocumentStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)

        fixture.store.renderingController.setAppearanceOverride(testAppearance)
        #expect(fixture.store.renderingController.needsAppearanceRender)

        try fixture.store.renderingController.renderImmediately(
            sourceMarkdown: fixture.store.document.sourceMarkdown,
            changedRegions: fixture.store.document.changedRegions,
            unsavedChangedRegions: fixture.store.sourceEditingController.unsavedChangedRegions,
            fileURL: fixture.store.document.fileURL,
            folderWatchSession: fixture.store.folderWatchDispatcher.activeFolderWatchSession
        )

        #expect(!fixture.store.renderingController.needsAppearanceRender)
    }
}
