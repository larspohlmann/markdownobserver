import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreSourceEditingTests {
    @Test @MainActor func startEditingCreatesCleanDraftState() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)

        fixture.store.editingFlow.startEditing()

        #expect(fixture.store.sourceEditingController.isSourceEditing)
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
        #expect(fixture.store.sourceEditingController.sourceEditorSeedMarkdown == "# Initial")
        #expect(fixture.store.sourceEditingController.unsavedChangedRegions.isEmpty)
    }

    @Test @MainActor func updatingDraftRendersPreviewFromDraftAndTracksUnsavedChanges() async throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()

        fixture.store.editingFlow.updateDraft("# Draft")

        #expect(fixture.store.sourceEditingController.isSourceEditing)
        #expect(fixture.store.sourceEditingController.hasUnsavedDraftChanges)
        #expect(fixture.store.document.sourceMarkdown == "# Draft")
        #expect(fixture.store.sourceEditingController.unsavedChangedRegions == [Self.sampleChangedRegion])

        let renderedDraft = await waitUntil {
            fixture.store.renderingController.renderedHTMLDocument.contains("# Draft")
        }

        #expect(renderedDraft)
        #expect(fixture.store.renderingController.renderedHTMLDocument.contains("# Draft"))
    }

    @Test @MainActor func saveDraftWritesToDiskAndShowsSavedDiffInPreview() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: false,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Saved Draft")

        fixture.store.editingFlow.save()

        let persistedMarkdown = try String(contentsOf: fixture.primaryFileURL, encoding: .utf8)
        #expect(persistedMarkdown == "# Saved Draft")
        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
        #expect(fixture.store.document.sourceMarkdown == "# Saved Draft")
        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(fixture.store.sourceEditingController.unsavedChangedRegions.isEmpty)
    }

    @Test @MainActor func autoOpenedWatchedFolderDraftSaveReacquiresFolderScopeWhenFileScopeFails() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }
        let normalizedPrimaryFilePath = ReaderFileRouting.normalizedFileURL(fixture.primaryFileURL).path
        let normalizedFolderPath = ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL).path

        let folderOptions = FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
        let session = FolderWatchSession(
            folderURL: fixture.temporaryDirectoryURL,
            options: folderOptions,
            startedAt: .now
        )
        fixture.settings.addRecentWatchedFolder(fixture.temporaryDirectoryURL, options: folderOptions)
        fixture.securityScope.didStartAccessResponsesByPath[fixture.primaryFileURL.path] = [false, true]
        fixture.securityScope.didStartAccessResponsesByPath[normalizedPrimaryFilePath] = [false, true]
        fixture.securityScope.didStartAccessByPath[fixture.temporaryDirectoryURL.path] = true
        fixture.securityScope.didStartAccessByPath[normalizedFolderPath] = true

        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session
        )
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Autoloaded Save")

        fixture.store.editingFlow.save()

        let persistedMarkdown = try String(contentsOf: fixture.primaryFileURL, encoding: .utf8)
        #expect(persistedMarkdown == "# Autoloaded Save")
        #expect(
            fixture.store.folderWatchDispatcher.activeFolderWatchSession.map { ReaderFileRouting.normalizedFileURL($0.folderURL).path } == normalizedFolderPath
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

        let options = FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly)
        let session = FolderWatchSession(
            folderURL: fixture.temporaryDirectoryURL,
            options: options,
            startedAt: .now
        )
        fixture.store.folderWatchDispatcher.setSession(session)

        let permissionDeniedError = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let result = fixture.store.securityScopeResolver.tryReauthorizeWatchedFolder(
            after: permissionDeniedError,
            for: fixture.primaryFileURL,
            folderWatchSession: fixture.store.folderWatchDispatcher.activeFolderWatchSession
        )
        if let updatedSession = result.updatedSession {
            fixture.store.folderWatchDispatcher.setSession(updatedSession)
        }

        #expect(result.succeeded)
        #expect(requestedFolderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.store.folderWatchDispatcher.activeFolderWatchSession?.folderURL == ReaderFileRouting.normalizedFileURL(fixture.temporaryDirectoryURL))
        #expect(fixture.settings.recordedRecentWatchedFolders.first?.folderPath == fixture.temporaryDirectoryURL.path)
        #expect(fixture.securityScope.accessedURLs.contains(where: { $0.path == fixture.temporaryDirectoryURL.path }))
    }

    @Test @MainActor func observedFileChangeAfterSavingDraftPreservesSavedDiffAndSkipsExternalState() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Saved Draft")

        fixture.store.editingFlow.save()
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.sourceMarkdown == "# Saved Draft")
        #expect(fixture.store.document.changedRegions == [Self.sampleChangedRegion])
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.store.externalChange.lastExternalChangeAt == nil)
        #expect(fixture.notifier.fileChangeNotifications.isEmpty)
    }

    @Test @MainActor func discardDraftRestoresSavedContent() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Draft")

        fixture.store.editingFlow.discard()

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
        #expect(fixture.store.sourceEditingController.unsavedChangedRegions.isEmpty)
        #expect(fixture.store.renderingController.renderedHTMLDocument.contains("# Initial"))
    }

    @Test @MainActor func externalChangeWhileEditingKeepsDraftInMemory() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Draft")
        fixture.write(content: "# External", to: fixture.primaryFileURL)

        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.sourceEditingController.isSourceEditing)
        #expect(fixture.store.document.sourceMarkdown == "# Draft")
        #expect(fixture.store.externalChange.hasUnacknowledgedExternalChange)
    }

    @Test @MainActor func discardAfterExternalChangeReloadsCurrentDiskVersion() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            changedRegionsForModifiedContent: [Self.sampleChangedRegion]
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Draft")
        fixture.write(content: "# External", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        fixture.store.editingFlow.discard()

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
        #expect(!fixture.store.externalChange.hasUnacknowledgedExternalChange)
        #expect(fixture.store.document.sourceMarkdown == "# External")
    }

    // MARK: - Guard paths

    @Test @MainActor func startEditingIsNoOpWhenNoDocumentIsOpen() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // No openFile call — store has no open document.
        fixture.store.editingFlow.startEditing()

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
    }

    @Test @MainActor func startEditingIsNoOpWhenCurrentFileIsMissing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.delete(fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        #expect(fixture.store.document.isCurrentFileMissing)

        fixture.store.editingFlow.startEditing()

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
    }

    @Test @MainActor func startEditingIsNoOpWhenAlreadyEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.store.editingFlow.startEditing()
        fixture.store.editingFlow.updateDraft("# Draft")

        // Second call while already editing must not reset the draft.
        fixture.store.editingFlow.startEditing()

        #expect(fixture.store.sourceEditingController.isSourceEditing)
        #expect(fixture.store.document.sourceMarkdown == "# Draft")
    }

    @Test @MainActor func updateDraftIsNoOpWhenNotEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        // updateSourceDraft without startEditingSource — must be a no-op.
        fixture.store.editingFlow.updateDraft("# Should Not Apply")

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
        #expect(!fixture.store.sourceEditingController.hasUnsavedDraftChanges)
    }

    @Test @MainActor func discardDraftIsNoOpWhenNotEditing() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        // discardSourceDraft without an active editing session must be a no-op.
        fixture.store.editingFlow.discard()

        #expect(!fixture.store.sourceEditingController.isSourceEditing)
        #expect(fixture.store.document.sourceMarkdown == "# Initial")
    }
}

private extension ReaderStoreSourceEditingTests {
    static var sampleChangedRegion: ChangedRegion {
        ChangedRegion(blockIndex: 0, lineRange: 1...1, kind: .edited)
    }
}

// ReaderSourceEditingCoordinatorTests removed — behavior covered by ReaderSourceEditingControllerTests