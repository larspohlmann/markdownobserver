import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreSourceEditingTests {
    @Test @MainActor func startEditingCreatesCleanDraftState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.startEditingSource()

        #expect(fixture.store.isSourceEditing)
        #expect(!fixture.store.hasUnsavedDraftChanges)
        #expect(fixture.store.sourceMarkdown == "# Initial")
        #expect(fixture.store.sourceEditorSeedMarkdown == "# Initial")
        #expect(fixture.store.unsavedChangedRegions.isEmpty)
    }

    @Test @MainActor func updatingDraftRendersPreviewFromDraftAndTracksUnsavedChanges() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()

        fixture.store.updateSourceDraft("# Draft")

        #expect(fixture.store.isSourceEditing)
        #expect(fixture.store.hasUnsavedDraftChanges)
        #expect(fixture.store.sourceMarkdown == "# Draft")
        #expect(fixture.store.unsavedChangedRegions == [Self.sampleChangedRegion])

        let renderedDraft = await waitUntil {
            fixture.store.renderedHTMLDocument.contains("# Draft")
        }

        #expect(renderedDraft)
        #expect(fixture.store.renderedHTMLDocument.contains("# Draft"))
    }

    @Test @MainActor func saveDraftWritesToDiskAndShowsSavedDiffInPreview() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Saved Draft")

        fixture.store.saveSourceDraft()

        let persistedMarkdown = try String(contentsOf: fixture.primaryFileURL, encoding: .utf8)
        #expect(persistedMarkdown == "# Saved Draft")
        #expect(!fixture.store.isSourceEditing)
        #expect(!fixture.store.hasUnsavedDraftChanges)
        #expect(fixture.store.sourceMarkdown == "# Saved Draft")
        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.unsavedChangedRegions.isEmpty)
    }

    @Test @MainActor func autoOpenedWatchedFolderDraftSaveReacquiresFolderScopeWhenFileScopeFails() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        let folderOptions = ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(
            folderURL: fixture.temporaryDirectoryURL,
            options: folderOptions,
            startedAt: .now
        )
        fixture.settings.addRecentWatchedFolder(fixture.temporaryDirectoryURL, options: folderOptions)
        fixture.securityScope.didStartAccessResponsesByPath[fixture.primaryFileURL.path] = [false, true]
        fixture.securityScope.didStartAccessByPath[fixture.temporaryDirectoryURL.path] = true

        fixture.store.openFile(
            at: fixture.primaryFileURL,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session
        )
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Autoloaded Save")

        fixture.store.saveSourceDraft()

        let persistedMarkdown = try String(contentsOf: fixture.primaryFileURL, encoding: .utf8)
        #expect(persistedMarkdown == "# Autoloaded Save")
        #expect(fixture.store.activeFolderWatchSession?.folderURL.path == fixture.temporaryDirectoryURL.path)
        #expect(fixture.securityScope.accessedURLs.filter { $0.path == fixture.primaryFileURL.path }.count == 2)
        #expect(fixture.securityScope.accessedURLs.contains(where: { $0.path == fixture.temporaryDirectoryURL.path }))
    }

    @Test @MainActor func observedFileChangeAfterSavingDraftPreservesSavedDiffAndSkipsExternalState() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Saved Draft")

        fixture.store.saveSourceDraft()
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.sourceMarkdown == "# Saved Draft")
        #expect(fixture.store.changedRegions == [Self.sampleChangedRegion])
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.store.lastExternalChangeAt == nil)
        #expect(fixture.notifier.externalChangeNotifications.isEmpty)
    }

    @Test @MainActor func discardDraftRestoresSavedContent() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Draft")

        fixture.store.discardSourceDraft()

        #expect(!fixture.store.isSourceEditing)
        #expect(!fixture.store.hasUnsavedDraftChanges)
        #expect(fixture.store.sourceMarkdown == "# Initial")
        #expect(fixture.store.unsavedChangedRegions.isEmpty)
        #expect(fixture.store.renderedHTMLDocument.contains("# Initial"))
    }

    @Test @MainActor func externalChangeWhileEditingKeepsDraftInMemory() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Draft")
        fixture.write(content: "# External", to: fixture.primaryFileURL)

        fixture.store.handleObservedFileChange()

        #expect(fixture.store.isSourceEditing)
        #expect(fixture.store.sourceMarkdown == "# Draft")
        #expect(fixture.store.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func discardAfterExternalChangeReloadsCurrentDiskVersion() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Draft")
        fixture.write(content: "# External", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        fixture.store.discardSourceDraft()

        #expect(!fixture.store.isSourceEditing)
        #expect(!fixture.store.hasUnsavedDraftChanges)
        #expect(!fixture.store.hasUnacknowledgedExternalChange)
        #expect(fixture.store.sourceMarkdown == "# External")
    }
}

private extension ReaderStoreSourceEditingTests {
    static var sampleChangedRegion: ChangedRegion {
        ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)
    }
}