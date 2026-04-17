import Foundation
import Testing
@testable import minimark

@Suite("Edit Folder Watch Exclusions")
@MainActor
struct EditFolderWatchExclusionsTests {

    private func makeTemporaryFolder(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-edit-excl-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func updateFavoriteExclusionsPreservesBookmarkData() throws {
        let folderURL = try makeTemporaryFolder(name: "bookmark")
        let store = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-bookmark.\(UUID().uuidString)"
        )

        let options = FolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "Test Folder",
            folderURL: folderURL,
            options: options
        )

        let favorite = store.currentSettings.favoriteWatchedFolders.first!
        let originalBookmarkData = favorite.bookmarkData
        #expect(originalBookmarkData != nil)

        store.updateFavoriteWatchedFolderExclusions(
            id: favorite.id,
            excludedSubdirectoryPaths: [folderURL.path + "/excluded"]
        )

        let updated = store.currentSettings.favoriteWatchedFolders.first!
        #expect(updated.bookmarkData == originalBookmarkData)
        #expect(updated.options.excludedSubdirectoryPaths == [folderURL.path + "/excluded"])
        #expect(updated.options.openMode == .openAllMarkdownFiles)
        #expect(updated.options.scope == .includeSubfolders)
        #expect(updated.id == favorite.id)
        #expect(updated.name == favorite.name)
        #expect(updated.folderPath == favorite.folderPath)

        try? FileManager.default.removeItem(at: folderURL)
    }

    @Test func updateFavoriteExclusionsNoOpWhenUnchanged() throws {
        let folderURL = try makeTemporaryFolder(name: "noop")
        let store = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-noop.\(UUID().uuidString)"
        )

        let exclusions = [folderURL.path + "/excluded"]

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: exclusions
            )
        )

        let favoriteBefore = store.currentSettings.favoriteWatchedFolders.first!
        store.updateFavoriteWatchedFolderExclusions(
            id: favoriteBefore.id,
            excludedSubdirectoryPaths: exclusions
        )

        let favoriteAfter = store.currentSettings.favoriteWatchedFolders.first!
        #expect(favoriteBefore == favoriteAfter)

        try? FileManager.default.removeItem(at: folderURL)
    }

    @Test func updateFavoriteExclusionsNoOpForUnknownID() throws {
        let folderURL = try makeTemporaryFolder(name: "unknown")
        let store = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-unknown.\(UUID().uuidString)"
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders
            )
        )

        let countBefore = store.currentSettings.favoriteWatchedFolders.count
        store.updateFavoriteWatchedFolderExclusions(
            id: UUID(),
            excludedSubdirectoryPaths: ["/some/path"]
        )
        #expect(store.currentSettings.favoriteWatchedFolders.count == countBefore)

        try? FileManager.default.removeItem(at: folderURL)
    }

    @Test func updateFavoriteExclusionsPreservesAllOtherProperties() throws {
        let folderURL = try makeTemporaryFolder(name: "props")
        let store = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-props.\(UUID().uuidString)"
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders
            )
        )

        let favoriteBefore = store.currentSettings.favoriteWatchedFolders.first!
        let originalBookmark = favoriteBefore.bookmarkData

        store.updateFavoriteWatchedFolderExclusions(
            id: favoriteBefore.id,
            excludedSubdirectoryPaths: [folderURL.path + "/new-excluded"]
        )

        let updated = store.currentSettings.favoriteWatchedFolders.first!
        #expect(updated.bookmarkData == originalBookmark)
        #expect(updated.allKnownRelativePaths == favoriteBefore.allKnownRelativePaths)
        #expect(updated.workspaceState == favoriteBefore.workspaceState)
        #expect(updated.createdAt == favoriteBefore.createdAt)

        try? FileManager.default.removeItem(at: folderURL)
    }

    @Test func excludedSelectedDocumentTriggersFallbackToNewest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-excl-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileA = tempDir.appendingPathComponent("a.md")
        let fileB = tempDir.appendingPathComponent("b.md")
        try "# A (older)".write(to: fileA, atomically: true, encoding: .utf8)
        try "# B (newer)".write(to: fileB, atomically: true, encoding: .utf8)

        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-fallback.\(UUID().uuidString)"
        )

        var createdFileWatchers: [TestFileWatcher] = []
        let controllerWatcher = TestFolderWatcher()
        let controller = ReaderSidebarDocumentController(
            settingsStore: settingsStore,
            makeReaderStore: {
                let fw = TestFileWatcher()
                createdFileWatchers.append(fw)
                let securityScopeResolver = SecurityScopeResolver(
                    securityScope: TestSecurityScopeAccess(),
                    settingsStore: settingsStore,
                    requestWatchedFolderReauthorization: { _ in nil }
                )
                return ReaderStore(
                    rendering: RenderingDependencies(
                        renderer: TestMarkdownRenderer(), differ: TestChangedRegionDiffer()
                    ),
                    file: FileDependencies(
                        watcher: fw, io: ReaderDocumentIOService(), actions: TestReaderFileActions()
                    ),
                    folderWatch: FolderWatchDependencies(
                        autoOpenPlanner: FolderWatchAutoOpenPlanner(),
                        settler: ReaderAutoOpenSettler(settlingInterval: 1.0),
                        systemNotifier: TestReaderSystemNotifier()
                    ),
                    settingsStore: settingsStore,
                    securityScopeResolver: securityScopeResolver
                )
            },
            makeFolderWatchController: {
                FolderWatchController(
                    folderWatcher: controllerWatcher,
                    settingsStore: settingsStore,
                    securityScope: TestSecurityScopeAccess(),
                    systemNotifier: TestReaderSystemNotifier(),
                    folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
                )
            }
        )

        let coordinator = FileOpenCoordinator(controller: controller)
        try controller.folderWatchCoordinator.startWatchingFolder(
            folderURL: tempDir,
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly
            ),
            performInitialAutoOpen: false
        )

        coordinator.open(FileOpenRequest(
            fileURLs: [fileA, fileB],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        #expect(controller.documents.count == 2)

        let docA = controller.documents.first { $0.readerStore.document.fileURL == fileA }
        #expect(docA != nil)
        controller.selectDocument(docA?.id)
        #expect(controller.selectedDocument?.readerStore.document.fileURL == fileA)

        controller.closeDocument(docA!.id)

        #expect(controller.documents.count == 1)
        let selected = controller.selectedDocument
        #expect(selected != nil)
        #expect(selected?.readerStore.document.fileURL == fileB)
        #expect(selected?.readerStore.document.isDeferredDocument == false)

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func updateExclusionsPreservesSessionProperties() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder", isDirectory: true)
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
        let initialOptions = FolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: [normalizedFolderURL.path + "/excluded"]
        )

        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.edit-excl-restart.\(UUID().uuidString)"
        )
        let controller = FolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(folderURL: folderURL, options: initialOptions, performInitialAutoOpen: false)
        try controller.updateExcludedSubdirectories([])

        let session = controller.activeFolderWatchSession
        #expect(session != nil)
        #expect(session?.options.excludedSubdirectoryPaths == [])
        #expect(session?.options.openMode == .openAllMarkdownFiles)
        #expect(session?.options.scope == .includeSubfolders)
        #expect(session?.folderURL == normalizedFolderURL)
    }
}
