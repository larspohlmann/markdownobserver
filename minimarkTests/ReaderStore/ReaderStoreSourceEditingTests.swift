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
        let normalizedPrimaryFilePath = ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL).path
        let normalizedFolderPath = ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL).path

        let folderOptions = ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(
            folderURL: fixture.temporaryDirectoryURL,
            options: folderOptions,
            startedAt: .now
        )
        fixture.settings.addRecentWatchedFolder(fixture.temporaryDirectoryURL, options: folderOptions)
        fixture.securityScope.didStartAccessResponsesByPath[fixture.primaryFileURL.path] = [false, true]
        fixture.securityScope.didStartAccessResponsesByPath[normalizedPrimaryFilePath] = [false, true]
        fixture.securityScope.didStartAccessByPath[fixture.temporaryDirectoryURL.path] = true
        fixture.securityScope.didStartAccessByPath[normalizedFolderPath] = true

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
        #expect(
            fixture.store.activeFolderWatchSession.map { ReaderFileRouting.normalizedFileURL($0.folderURL).path } == normalizedFolderPath
        )
        #expect(
            fixture.securityScope.accessedURLs
                .map(ReaderFileRouting.normalizedFileURL)
                .contains(where: { $0.path == normalizedPrimaryFilePath })
        )
        #expect(
            fixture.securityScope.accessedURLs
                .map(ReaderFileRouting.normalizedFileURL)
                .contains(where: { $0.path == normalizedFolderPath })
        )
    }

    @Test @MainActor func watchedFolderReauthorizationRequestsMatchingFolderAndRefreshesScopeToken() throws {
        var requestedFolderURL: URL?
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            requestWatchedFolderReauthorization: { folderURL in
                requestedFolderURL = folderURL
                return folderURL
            }
        )
        defer { fixture.cleanup() }

        let options = ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = ReaderFolderWatchSession(
            folderURL: fixture.temporaryDirectoryURL,
            options: options,
            startedAt: .now
        )
        fixture.store.setActiveFolderWatchSession(session)

        let permissionDeniedError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let didReauthorize = fixture.store.tryReauthorizeWatchedFolderIfNeeded(
            after: permissionDeniedError,
            for: fixture.primaryFileURL
        )

        #expect(didReauthorize)
        #expect(requestedFolderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.store.activeFolderWatchSession?.folderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.settings.recordedRecentWatchedFolders.first?.folderPath == fixture.temporaryDirectoryURL.path)
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

    // MARK: - Guard paths

    @Test @MainActor func startEditingIsNoOpWhenNoDocumentIsOpen() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // No openFile call — store has no open document.
        fixture.store.startEditingSource()

        #expect(!fixture.store.isSourceEditing)
        #expect(!fixture.store.hasUnsavedDraftChanges)
    }

    @Test @MainActor func startEditingIsNoOpWhenCurrentFileIsMissing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.delete(fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        #expect(fixture.store.isCurrentFileMissing)

        fixture.store.startEditingSource()

        #expect(!fixture.store.isSourceEditing)
    }

    @Test @MainActor func startEditingIsNoOpWhenAlreadyEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.store.startEditingSource()
        fixture.store.updateSourceDraft("# Draft")

        // Second call while already editing must not reset the draft.
        fixture.store.startEditingSource()

        #expect(fixture.store.isSourceEditing)
        #expect(fixture.store.sourceMarkdown == "# Draft")
    }

    @Test @MainActor func updateDraftIsNoOpWhenNotEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        // updateSourceDraft without startEditingSource — must be a no-op.
        fixture.store.updateSourceDraft("# Should Not Apply")

        #expect(!fixture.store.isSourceEditing)
        #expect(fixture.store.sourceMarkdown == "# Initial")
        #expect(!fixture.store.hasUnsavedDraftChanges)
    }

    @Test @MainActor func discardDraftIsNoOpWhenNotEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        // discardSourceDraft without an active editing session must be a no-op.
        fixture.store.discardSourceDraft()

        #expect(!fixture.store.isSourceEditing)
        #expect(fixture.store.sourceMarkdown == "# Initial")
    }
}

private extension ReaderStoreSourceEditingTests {
    static var sampleChangedRegion: ChangedRegion {
        ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)
    }
}

struct ReaderSourceEditingCoordinatorTests {
    @Test func beginSessionStartsCleanEditingState() {
        let coordinator = ReaderSourceEditingCoordinator()

        let transition = coordinator.beginSession(markdown: "# Initial")

        #expect(transition.draftMarkdown == "# Initial")
        #expect(transition.sourceMarkdown == "# Initial")
        #expect(transition.sourceEditorSeedMarkdown == "# Initial")
        #expect(transition.unsavedChangedRegions.isEmpty)
        #expect(transition.isSourceEditing)
        #expect(!transition.hasUnsavedDraftChanges)
    }

    @Test func updateDraftTracksUnsavedStateAgainstBaseline() {
        let coordinator = ReaderSourceEditingCoordinator()
        let changedRegions = [ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)]

        let transition = coordinator.updateDraft(
            markdown: "# Draft",
            sourceEditorSeedMarkdown: "# Initial",
            diffBaselineMarkdown: "# Initial",
            unsavedChangedRegions: changedRegions
        )

        #expect(transition.draftMarkdown == "# Draft")
        #expect(transition.sourceMarkdown == "# Draft")
        #expect(transition.sourceEditorSeedMarkdown == "# Initial")
        #expect(transition.unsavedChangedRegions == changedRegions)
        #expect(transition.isSourceEditing)
        #expect(transition.hasUnsavedDraftChanges)
    }

    @Test func finishSessionResetsEditingFlags() {
        let coordinator = ReaderSourceEditingCoordinator()

        let transition = coordinator.finishSession(markdown: "# Saved")

        #expect(transition.draftMarkdown == nil)
        #expect(transition.sourceMarkdown == "# Saved")
        #expect(transition.sourceEditorSeedMarkdown == "# Saved")
        #expect(transition.unsavedChangedRegions.isEmpty)
        #expect(!transition.isSourceEditing)
        #expect(!transition.hasUnsavedDraftChanges)
    }
}