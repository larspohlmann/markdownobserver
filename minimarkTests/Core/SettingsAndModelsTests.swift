//
//  SettingsAndModelsTests.swift
//  minimarkTests
//

import CoreGraphics
import Foundation
import Testing
import UserNotifications
@testable import minimark

@Suite(.serialized)
struct SettingsAndModelsTests {
    @Test @MainActor func readerWindowSeedCodableRoundTripPreservesIdentityFilePathAndWatchSession() throws {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let fileURL = URL(fileURLWithPath: "/tmp/watch.md")
        let watchSession = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders),
            startedAt: Date(timeIntervalSince1970: 12345)
        )
        let seed = WindowSeed(
            id: id,
            fileURL: fileURL,
            folderWatchSession: watchSession,
            openOrigin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Previous"
        )

        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(WindowSeed.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.filePath == fileURL.path)
        #expect(decoded.fileURL?.path == fileURL.path)
        #expect(decoded.folderWatchSession == watchSession)
        #expect(decoded.openOrigin == .folderWatchAutoOpen)
        #expect(decoded.initialDiffBaselineMarkdown == "# Previous")
    }

    @Test @MainActor func readerWindowSeedCodableRoundTripPreservesRecentWatchedFolderRequest() throws {
        let entry = RecentWatchedFolder(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders)
        )
        let seed = WindowSeed(recentWatchedFolder: entry)

        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(WindowSeed.self, from: data)

        #expect(decoded.recentWatchedFolder?.folderPath == entry.folderPath)
        #expect(decoded.recentWatchedFolder?.options == entry.options)
    }

    @Test @MainActor func readerWindowSeedCodableRoundTripPreservesRecentOpenedFileRequest() throws {
        let entry = RecentOpenedFile(fileURL: URL(fileURLWithPath: "/tmp/recent.md"))
        let seed = WindowSeed(recentOpenedFile: entry)

        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(WindowSeed.self, from: data)

        #expect(decoded.recentOpenedFile?.filePath == entry.filePath)
    }

    @Test @MainActor func readerWindowSeedDefaultOriginIsManual() {
        let seed = WindowSeed(fileURL: URL(fileURLWithPath: "/tmp/default-origin.md"))

        #expect(seed.openOrigin == .manual)
    }

    @Test func readerWindowTitleMutationSkipsWritesWhenTitlesAlreadyMatch() {
        let mutation = WindowTitleFormatter.mutation(
            resolvedTitle: "notes.md - MarkdownObserver",
            currentEffectiveTitle: "notes.md - MarkdownObserver",
            currentHostWindowTitle: "notes.md - MarkdownObserver"
        )

        #expect(!mutation.shouldUpdateEffectiveTitle)
        #expect(!mutation.shouldWriteHostWindowTitle)
    }

    @Test func readerWindowTitleMutationRequestsWritesWhenTitlesDiffer() {
        let mutation = WindowTitleFormatter.mutation(
            resolvedTitle: "* notes.md - MarkdownObserver | docs",
            currentEffectiveTitle: "notes.md - MarkdownObserver",
            currentHostWindowTitle: "notes.md - MarkdownObserver"
        )

        #expect(mutation.shouldUpdateEffectiveTitle)
        #expect(mutation.shouldWriteHostWindowTitle)
    }

    @Test func readerWindowDefaultsUseBaseSizeWhenVisibleFrameCanFitIt() {
        let size = WindowDefaults.size(forVisibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 2200))

        #expect(size.width == WindowDefaults.baseWidth)
        #expect(size.height == WindowDefaults.baseHeight)
    }

    @Test func readerWindowDefaultsClampToVisibleHeightWhilePreservingAspectRatio() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = WindowDefaults.size(forVisibleFrame: visibleFrame)
        let maxHeight = visibleFrame.height * WindowDefaults.fittedHeightUsage
        let scale = maxHeight / WindowDefaults.baseHeight

        #expect(size.width == WindowDefaults.baseWidth * scale)
        #expect(size.height == WindowDefaults.baseHeight * scale)
    }

    @Test func readerWindowDefaultsKeepMinimumUsableWidthWhenScreenIsCloseToFittingIt() {
        let minimumUsableHeight = WindowDefaults.minimumUsableWidth * WindowDefaults.letterAspectRatio
        let visibleFrame = CGRect(
            x: 0,
            y: 0,
            width: 1440,
            height: minimumUsableHeight * WindowDefaults.minimumUsableHeightTolerance
        )

        let size = WindowDefaults.size(forVisibleFrame: visibleFrame)

        #expect(size.width == WindowDefaults.minimumUsableWidth)
        #expect(size.height == minimumUsableHeight)
    }

    @Test func readerWindowDefaultsPreferFittedSizeWhenMinimumUsableWidthWouldStillBeTooTall() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1280, height: 780)
        let size = WindowDefaults.size(forVisibleFrame: visibleFrame)

        #expect(size.width < WindowDefaults.minimumUsableWidth)
        #expect(size.height == visibleFrame.height * WindowDefaults.fittedHeightUsage)
    }

    @Test @MainActor func readerSettingsStorePersistsMultiFileDisplayMode() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.updateMultiFileDisplayMode(.sidebarRight)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.multiFileDisplayMode == .sidebarRight)
    }

    @Test @MainActor func readerSettingsStorePersistsAppAppearance() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.app-appearance.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.updateAppAppearance(.dark)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.appAppearance == .dark)
    }

    @Test @MainActor func readerSettingsStorePersistsSidebarSortMode() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.sidebar-sort.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.updateSidebarSortMode(.lastChangedNewestFirst)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.sidebarSortMode == .lastChangedNewestFirst)
    }

    @Test @MainActor func readerSettingsStorePersistsSidebarGroupSortMode() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.sidebar-group-sort.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.updateSidebarGroupSortMode(.nameAscending)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.sidebarGroupSortMode == .nameAscending)
    }

    @Test @MainActor func readerSettingsStorePersistsNotificationsEnabled() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.notifications.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.updateNotificationsEnabled(false)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(!reloadedStore.currentSettings.notificationsEnabled)
    }

    @Test @MainActor func readerSettingsStoreDefaultsToSidebarDisplayMode() {
        let storage = TestSettingsKeyValueStorage()
        let store = SettingsStore(storage: storage, storageKey: "reader.settings.default-mode.tests")

        #expect(store.currentSettings.appAppearance == .system)
        #expect(store.currentSettings.multiFileDisplayMode == .sidebarLeft)
        #expect(store.currentSettings.notificationsEnabled)
        #expect(store.currentSettings.sidebarSortMode == .openOrder)
        #expect(store.currentSettings.sidebarGroupSortMode == .lastChangedNewestFirst)
        #expect(store.currentSettings.recentWatchedFolders.isEmpty)
        #expect(store.currentSettings.recentManuallyOpenedFiles.isEmpty)
    }

    @Test @MainActor func readerSettingsStorePersistsRecentHistoryAndCapsEntries() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.recent-history.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        for index in 0..<20 {
            store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/file-\(index).md"))
            store.addRecentWatchedFolder(
                URL(fileURLWithPath: "/tmp/folder-\(index)"),
                options: .init(
                    openMode: index.isMultiple(of: 2) ? .openAllMarkdownFiles : .watchChangesOnly,
                    scope: .selectedFolderOnly
                )
            )
        }

        store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/file-3.md"))
        store.addRecentWatchedFolder(
            URL(fileURLWithPath: "/tmp/folder-3"),
            options: .init(openMode: .watchChangesOnly, scope: .includeSubfolders)
        )

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)

        #expect(reloadedStore.currentSettings.recentManuallyOpenedFiles.count == 15)
        #expect(reloadedStore.currentSettings.recentWatchedFolders.count == 15)
        #expect(reloadedStore.currentSettings.recentManuallyOpenedFiles.first?.filePath == "/tmp/file-3.md")
        #expect(reloadedStore.currentSettings.recentWatchedFolders.first?.folderPath == "/tmp/folder-3")
        #expect(reloadedStore.currentSettings.recentWatchedFolders.first?.options.scope == .includeSubfolders)
    }

    @Test @MainActor func readerSettingsStoreRecentFileResolverClearsInvalidBookmarkData() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.recent-file.invalid-bookmark.tests"
        let fileURL = URL(fileURLWithPath: "/tmp/invalid-bookmark.md")
        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [
                RecentOpenedFile(filePath: fileURL.path, bookmarkData: Data([0x00, 0x01, 0x02]))
            ]
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(storage: storage, storageKey: storageKey)
        let resolvedURL = store.resolvedRecentManuallyOpenedFileURL(matching: fileURL)

        #expect(resolvedURL?.path == fileURL.path)
        #expect(store.currentSettings.recentManuallyOpenedFiles.first?.bookmarkData == nil)
    }

    @Test @MainActor func readerSettingsStoreRecentWatchedFolderResolverClearsInvalidBookmarkData() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.recent-folder.invalid-bookmark.tests"
        let folderURL = URL(fileURLWithPath: "/tmp/invalid-watch-folder", isDirectory: true)
        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [
                RecentWatchedFolder(
                    folderPath: folderURL.path,
                    options: .default,
                    bookmarkData: Data([0xAA, 0xBB, 0xCC])
                )
            ],
            recentManuallyOpenedFiles: []
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(storage: storage, storageKey: storageKey)
        let resolvedURL = store.resolvedRecentWatchedFolderURL(matching: folderURL)

        #expect(resolvedURL?.path == folderURL.path)
        #expect(store.currentSettings.recentWatchedFolders.first?.bookmarkData == nil)
    }

    @Test @MainActor func readerSettingsStoreRecentWatchedFolderResolverRefreshesStaleBookmarkData() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.recent-folder.stale-bookmark.tests"
        let folderURL = URL(fileURLWithPath: "/tmp/stale-watch-folder", isDirectory: true)
        let originalBookmarkData = Data([0x01, 0x02, 0x03])
        let refreshedBookmarkData = Data([0x10, 0x20, 0x30])
        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [
                RecentWatchedFolder(
                    folderPath: folderURL.path,
                    options: .default,
                    bookmarkData: originalBookmarkData
                )
            ],
            recentManuallyOpenedFiles: []
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        var resolvedBookmarkDataValues: [Data] = []
        var createdBookmarkURLs: [URL] = []
        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            bookmarkResolver: { bookmarkData in
                resolvedBookmarkDataValues.append(bookmarkData)
                return (folderURL, true)
            },
            bookmarkCreator: { resolvedURL in
                createdBookmarkURLs.append(resolvedURL)
                return refreshedBookmarkData
            }
        )

        let resolvedURL = store.resolvedRecentWatchedFolderURL(matching: folderURL)

        #expect(resolvedURL?.path == folderURL.path)
        #expect(resolvedBookmarkDataValues == [originalBookmarkData])
        #expect(createdBookmarkURLs == [folderURL])
        #expect(store.currentSettings.recentWatchedFolders.first?.bookmarkData == refreshedBookmarkData)
    }

    @Test @MainActor func readerSettingsStoreRecentFileResolverPreservesValidBookmarkData() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.recent-file.valid-bookmark.tests"
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-settings-valid-bookmark-\(UUID().uuidString).md")
        try "# hello".write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let entry = RecentOpenedFile(fileURL: fileURL)
        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [entry]
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(storage: storage, storageKey: storageKey)
        let resolvedURL = store.resolvedRecentManuallyOpenedFileURL(matching: fileURL)

        #expect(resolvedURL != nil)
        #expect(store.currentSettings.recentManuallyOpenedFiles.first?.bookmarkData != nil)
    }

    @Test func readerRecentHistoryMenuTitleAddsParentContextOnlyWhenNeeded() {
        let fileEntries = [
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/work/alpha/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/archive/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/archive/notes/ideas.md"))
        ]
        let folderEntries = [
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/alpha/docs"),
                options: .default
            ),
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/beta/docs"),
                options: .default
            ),
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/gamma/guides"),
                options: .default
            )
        ]

        #expect(RecentHistory.menuTitle(for: fileEntries[0], among: fileEntries) == "todo.md (alpha/notes)")
        #expect(RecentHistory.menuTitle(for: fileEntries[2], among: fileEntries) == "ideas.md")
        #expect(RecentHistory.menuTitle(for: folderEntries[0], among: folderEntries) == "docs (alpha)")
        #expect(RecentHistory.menuTitle(for: folderEntries[2], among: folderEntries) == "guides")
    }

    @Test func readerRecentHistoryMenuTitleAddsFilteredIndicatorForWatchedFolders() {
        let entries = [
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/alpha/docs"),
                options: FolderWatchOptions(
                    openMode: .watchChangesOnly,
                    scope: .includeSubfolders,
                    excludedSubdirectoryPaths: ["/work/alpha/docs/build"]
                )
            ),
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/beta/docs"),
                options: .default
            )
        ]

        #expect(
            RecentHistory.menuTitle(for: entries[0], among: entries) == "docs (alpha) [1 filtered folder]"
        )
        #expect(
            RecentHistory.menuTitle(for: entries[1], among: entries) == "docs (beta)"
        )
    }

    @Test func readerRecentHistoryMenuTitleOmitsFilteredIndicatorForSelectedFolderScope() {
        let entries = [
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/alpha/docs"),
                options: FolderWatchOptions(
                    openMode: .watchChangesOnly,
                    scope: .selectedFolderOnly,
                    excludedSubdirectoryPaths: ["/work/alpha/docs/build"]
                )
            ),
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/beta/docs"),
                options: .default
            )
        ]

        #expect(
            RecentHistory.menuTitle(for: entries[0], among: entries) == "docs (alpha)"
        )
    }

    @Test func readerRecentHistoryMenuTitlesDisambiguateMultipleDuplicateNames() {
        let entries = [
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/work/alpha/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/work/beta/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/work/gamma/tasks/todo.md"))
        ]

        let titlesByPath = RecentHistory.menuTitles(for: entries)
        #expect(titlesByPath[entries[0].filePath] == "todo.md (alpha/notes)")
        #expect(titlesByPath[entries[1].filePath] == "todo.md (beta/notes)")
        #expect(titlesByPath[entries[2].filePath] == "todo.md (tasks)")
    }

    @Test func readerRecentHistoryBulkMenuTitlesMatchPerEntryTitles() {
        let recentFiles = [
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/work/alpha/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/archive/notes/todo.md")),
            RecentOpenedFile(fileURL: URL(fileURLWithPath: "/archive/notes/ideas.md"))
        ]
        let recentFolders = [
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/alpha/docs"),
                options: FolderWatchOptions(
                    openMode: .watchChangesOnly,
                    scope: .includeSubfolders,
                    excludedSubdirectoryPaths: ["/work/alpha/docs/build"]
                )
            ),
            RecentWatchedFolder(
                folderURL: URL(fileURLWithPath: "/work/beta/docs"),
                options: .default
            )
        ]

        let fileTitlesByPath = RecentHistory.menuTitles(for: recentFiles)
        let folderTitlesByPath = RecentHistory.menuTitles(for: recentFolders)

        for entry in recentFiles {
            #expect(
                fileTitlesByPath[entry.filePath] == RecentHistory.menuTitle(for: entry, among: recentFiles)
            )
        }

        for entry in recentFolders {
            #expect(
                folderTitlesByPath[entry.folderPath] == RecentHistory.menuTitle(for: entry, among: recentFolders)
            )
        }
    }

    @Test @MainActor func readerSettingsStoreCoalescesPersistCallsWithinThrottleWindow() async {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.persist-throttle.tests"
        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            minimumPersistInterval: 0.5
        )

        store.updateBaseFontSize(16)
        #expect(storage.setCallCount == 1)

        store.updateBaseFontSize(17)
        store.updateBaseFontSize(18)
        #expect(storage.setCallCount == 1)

        try? await Task.sleep(for: .milliseconds(700))

        #expect(storage.setCallCount == 2)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.baseFontSize == 18)
    }

    // MARK: - Trusted Image Folders

    @Test @MainActor func trustedImageFolderInsertDeduplicatesAndPersists() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.trusted-image.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        let folderA = URL(fileURLWithPath: "/tmp/docs-a", isDirectory: true)
        let folderB = URL(fileURLWithPath: "/tmp/docs-b", isDirectory: true)

        store.addTrustedImageFolder(folderA)
        store.addTrustedImageFolder(folderB)
        store.addTrustedImageFolder(folderA) // duplicate

        #expect(store.currentSettings.trustedImageFolders.count == 2)
        #expect(store.currentSettings.trustedImageFolders[0].folderPath == folderA.path)
        #expect(store.currentSettings.trustedImageFolders[1].folderPath == folderB.path)
    }

    @Test @MainActor func trustedImageFolderResolvesContainingFolder() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.trusted-image-resolve.tests"
        let folderURL = URL(fileURLWithPath: "/tmp/my-notes", isDirectory: true)
        let resolvedURL = URL(fileURLWithPath: "/tmp/resolved-notes", isDirectory: true)
        let bookmarkData = Data([0x01, 0x02, 0x03])

        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [],
            trustedImageFolders: [
                TrustedImageFolder(folderPath: folderURL.path, bookmarkData: bookmarkData)
            ]
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            bookmarkResolver: { _ in (resolvedURL, false) }
        )

        let fileInFolder = URL(fileURLWithPath: "/tmp/my-notes/readme.md")
        let result = store.resolvedTrustedImageFolderURL(containing: fileInFolder)
        #expect(result?.path == resolvedURL.path)
    }

    @Test @MainActor func trustedImageFolderReturnsNilForFileOutsideTrustedFolders() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.trusted-image-outside.tests"
        let folderURL = URL(fileURLWithPath: "/tmp/my-notes", isDirectory: true)
        let bookmarkData = Data([0x01, 0x02, 0x03])

        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [],
            trustedImageFolders: [
                TrustedImageFolder(folderPath: folderURL.path, bookmarkData: bookmarkData)
            ]
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            bookmarkResolver: { _ in (folderURL, false) }
        )

        let fileOutside = URL(fileURLWithPath: "/tmp/other-folder/readme.md")
        let result = store.resolvedTrustedImageFolderURL(containing: fileOutside)
        #expect(result == nil)
    }

    @Test @MainActor func trustedImageFolderClearsInvalidBookmark() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.trusted-image-invalid.tests"
        let folderURL = URL(fileURLWithPath: "/tmp/invalid-trust", isDirectory: true)

        let seededSettings = Settings(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [],
            trustedImageFolders: [
                TrustedImageFolder(folderPath: folderURL.path, bookmarkData: Data([0xAA, 0xBB]))
            ]
        )
        storage.set(try JSONEncoder().encode(seededSettings), forKey: storageKey)

        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            bookmarkResolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let fileInFolder = URL(fileURLWithPath: "/tmp/invalid-trust/readme.md")
        let result = store.resolvedTrustedImageFolderURL(containing: fileInFolder)
        #expect(result == nil)
        #expect(store.currentSettings.trustedImageFolders.first?.bookmarkData == nil)
    }

    @Test func readerFolderWatchOptionsDecodesLegacyPayloadWithoutExclusions() throws {
        let legacyJSON = "{\"openMode\":\"watchChangesOnly\",\"scope\":\"includeSubfolders\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(FolderWatchOptions.self, from: legacyJSON)

        #expect(decoded.openMode == .watchChangesOnly)
        #expect(decoded.scope == .includeSubfolders)
        #expect(decoded.excludedSubdirectoryPaths.isEmpty)
    }

    @Test func readerSystemNotifierConfigureDoesNotRequestAuthorization() {
        let notificationCenter = TestUserNotificationCenter()
        let notifier = SystemNotifier(notificationCenter: notificationCenter)

        notifier.configure()

        #expect(notificationCenter.requestAuthorizationCallCount == 0)
        #expect(notificationCenter.delegate != nil)
    }

    @Test @MainActor func readerSystemNotifierConfigureRefreshesNotificationStatus() async {
        let notificationCenter = TestUserNotificationCenter()
        notificationCenter.currentNotificationSettings = UserNotificationSettings(
            authorizationStatus: .denied,
            alertSetting: .disabled,
            soundSetting: .disabled,
            notificationCenterSetting: .enabled
        )
        let notifier = SystemNotifier(notificationCenter: notificationCenter)

        notifier.configure()

        #expect(await waitUntil {
            notifier.notificationStatus.authorizationState == .denied
        })
        #expect(!notifier.notificationStatus.alertsEnabled)
        #expect(notifier.notificationStatus.notificationCenterEnabled)
    }

    @Test func readerSystemNotifierRequestsAuthorizationBeforePostingFirstNotification() throws {
        let notificationCenter = TestUserNotificationCenter()
        let notifier = SystemNotifier(notificationCenter: notificationCenter)
        let watchedFolderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let fileURL = watchedFolderURL.appendingPathComponent("roadmap.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .modified,
            watchedFolderURL: watchedFolderURL
        )

        #expect(notificationCenter.requestAuthorizationCallCount == 1)
        let requestAuthorizationIndex = try #require(notificationCenter.recordedEvents.firstIndex(of: "requestAuthorization"))
        let addIndex = try #require(notificationCenter.recordedEvents.firstIndex(of: "add"))
        #expect(notificationCenter.recordedEvents.first == "notificationSettings")
        #expect(notificationCenter.recordedEvents.filter { $0 == "notificationSettings" }.count >= 1)
        #expect(requestAuthorizationIndex < addIndex)

        let request = try #require(notificationCenter.addedRequests.first)
        #expect(request.trigger == nil)
        #expect(request.content.title == "🟡 Modified")
        #expect(request.content.subtitle == "roadmap.md")
        #expect(request.content.body == "")
        #expect(request.content.userInfo["filePath"] as? String == fileURL.path)
        #expect(request.content.userInfo["watchedFolderPath"] as? String == watchedFolderURL.path)
    }

    @Test func readerSystemNotifierRoutesNotificationClicksToTargetFocuser() {
        let notificationCenter = TestUserNotificationCenter()
        let focuser = TestNotificationTargetFocuser()
        let notifier = SystemNotifier(
            notificationCenter: notificationCenter,
            notificationTargetFocuser: focuser
        )

        notifier.handleNotificationResponseUserInfo([
            "filePath": "/tmp/notes/todo.md",
            "watchedFolderPath": "/tmp/notes"
        ])

        #expect(focuser.focusedTargets.count == 1)
        #expect(focuser.focusedTargets[0].fileURL == URL(fileURLWithPath: "/tmp/notes/todo.md"))
        #expect(focuser.focusedTargets[0].watchedFolderURL == URL(fileURLWithPath: "/tmp/notes"))
    }

    @Test func readerSystemNotifierSchedulesDelayedTestNotification() throws {
        let notificationCenter = TestUserNotificationCenter()
        notificationCenter.currentNotificationSettings = UserNotificationSettings(
            authorizationStatus: .authorized,
            alertSetting: .enabled,
            soundSetting: .disabled,
            notificationCenterSetting: .enabled
        )
        let notifier = SystemNotifier(notificationCenter: notificationCenter)

        notifier.sendTestNotification()

        let request = try #require(notificationCenter.addedRequests.first)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 5)
        #expect(request.content.title == "Test notification")
        #expect(request.content.body == "This test was scheduled by MarkdownObserver. Switch away from the app before it fires to verify background delivery.")
    }

    @Test func readerSystemNotifierPostsAddedNotificationWithCorrectContent() throws {
        let notificationCenter = TestUserNotificationCenter()
        let notifier = SystemNotifier(notificationCenter: notificationCenter)
        let watchedFolderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let fileURL = watchedFolderURL.appendingPathComponent("new-file.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .added,
            watchedFolderURL: watchedFolderURL
        )

        let request = try #require(notificationCenter.addedRequests.first)
        #expect(request.content.title == "🟢 Created")
        #expect(request.content.subtitle == "new-file.md")
        #expect(request.content.userInfo["filePath"] as? String == fileURL.path)
        #expect(request.content.userInfo["watchedFolderPath"] as? String == watchedFolderURL.path)
    }

    @Test func readerSystemNotifierPostsModifiedNotificationWithCorrectContent() throws {
        let notificationCenter = TestUserNotificationCenter()
        let notifier = SystemNotifier(notificationCenter: notificationCenter)
        let watchedFolderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let fileURL = watchedFolderURL.appendingPathComponent("edited.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .modified,
            watchedFolderURL: watchedFolderURL
        )

        let request = try #require(notificationCenter.addedRequests.first)
        #expect(request.content.title == "🟡 Modified")
        #expect(request.content.subtitle == "edited.md")
        #expect(request.content.userInfo["filePath"] as? String == fileURL.path)
        #expect(request.content.userInfo["watchedFolderPath"] as? String == watchedFolderURL.path)
    }

    @Test func readerSystemNotifierPostsDeletedNotificationWithCorrectContent() throws {
        let notificationCenter = TestUserNotificationCenter()
        let notifier = SystemNotifier(notificationCenter: notificationCenter)
        let watchedFolderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let fileURL = watchedFolderURL.appendingPathComponent("removed.md")

        notifier.notifyFileChanged(
            fileURL,
            changeKind: .deleted,
            watchedFolderURL: watchedFolderURL
        )

        let request = try #require(notificationCenter.addedRequests.first)
        #expect(request.content.title == "🔴 Deleted")
        #expect(request.content.subtitle == "removed.md")
        #expect(request.content.userInfo["filePath"] as? String == fileURL.path)
        #expect(request.content.userInfo["watchedFolderPath"] as? String == watchedFolderURL.path)
    }

    @Test @MainActor func readerSettingsStoreDecodesLegacySidebarModeAsSidebarLeftAndDefaultsAppAppearance() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.legacy-mode.tests"
        storage.set("{\"readerTheme\":\"blackOnWhite\",\"syntaxTheme\":\"monokai\",\"baseFontSize\":15,\"autoRefreshOnExternalChange\":true,\"multiFileDisplayMode\":\"sidebar\"}".data(using: .utf8), forKey: storageKey)

        let store = SettingsStore(storage: storage, storageKey: storageKey)

        #expect(store.currentSettings.appAppearance == .system)
        #expect(store.currentSettings.multiFileDisplayMode == .sidebarLeft)
        #expect(store.currentSettings.notificationsEnabled)
        #expect(store.currentSettings.sidebarSortMode == .openOrder)
        #expect(store.currentSettings.sidebarGroupSortMode == .lastChangedNewestFirst)
        #expect(store.currentSettings.recentWatchedFolders.isEmpty)
        #expect(store.currentSettings.recentManuallyOpenedFiles.isEmpty)
    }

    @Test @MainActor func readerSettingsStoreMigratesLegacyTabsModeWithoutResettingOtherSettings() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.legacy-tabs-mode.tests"
        storage.set(
            "{\"appAppearance\":\"dark\",\"readerTheme\":\"whiteOnBlack\",\"syntaxTheme\":\"xcode\",\"baseFontSize\":19,\"autoRefreshOnExternalChange\":false,\"notificationsEnabled\":false,\"multiFileDisplayMode\":\"tabs\",\"sidebarSortMode\":\"nameDescending\"}".data(using: .utf8),
            forKey: storageKey
        )

        let store = SettingsStore(storage: storage, storageKey: storageKey)

        #expect(store.currentSettings.appAppearance == .dark)
        #expect(store.currentSettings.readerTheme == .whiteOnBlack)
        #expect(store.currentSettings.syntaxTheme == .xcode)
        #expect(store.currentSettings.baseFontSize == 19)
        #expect(!store.currentSettings.autoRefreshOnExternalChange)
        #expect(!store.currentSettings.notificationsEnabled)
        #expect(store.currentSettings.multiFileDisplayMode == .sidebarLeft)
        #expect(store.currentSettings.sidebarSortMode == .nameDescending)
        #expect(store.currentSettings.sidebarGroupSortMode == .lastChangedNewestFirst)
        #expect(store.currentSettings.recentWatchedFolders.isEmpty)
        #expect(store.currentSettings.recentManuallyOpenedFiles.isEmpty)
    }

    @Test func sidebarSortModeNameAscendingSortsNamedFilesAndKeepsUntitledLast() {
        let items = [
            SidebarSortTestItem(id: "untitled", displayName: nil, lastChangedAt: nil),
            SidebarSortTestItem(id: "zeta", displayName: "zeta.md", lastChangedAt: nil),
            SidebarSortTestItem(id: "alpha", displayName: "alpha.md", lastChangedAt: nil)
        ]

        let ordered = SidebarSortMode.nameAscending.sorted(items) { item in
            SidebarSortDescriptor(displayName: item.displayName, lastChangedAt: item.lastChangedAt)
        }

        #expect(ordered.map(\.id) == ["alpha", "zeta", "untitled"])
    }

    @Test func sidebarSortModeNewestFirstUsesStableFallbackForEqualAndMissingDates() {
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)
        let items = [
            SidebarSortTestItem(id: "same-a", displayName: "same-a.md", lastChangedAt: olderDate),
            SidebarSortTestItem(id: "newest", displayName: "newest.md", lastChangedAt: newerDate),
            SidebarSortTestItem(id: "same-b", displayName: "same-b.md", lastChangedAt: olderDate),
            SidebarSortTestItem(id: "untitled", displayName: nil, lastChangedAt: nil)
        ]

        let ordered = SidebarSortMode.lastChangedNewestFirst.sorted(items) { item in
            SidebarSortDescriptor(displayName: item.displayName, lastChangedAt: item.lastChangedAt)
        }

        #expect(ordered.map(\.id) == ["newest", "same-a", "same-b", "untitled"])
    }

    @Test func readerMultiFileDisplayModeChangesNeverRequireRestartInSidebarOnlyMode() {
        #expect(!MultiFileDisplayMode.sidebarLeft.requiresRestart(from: .sidebarRight))
        #expect(!MultiFileDisplayMode.sidebarRight.requiresRestart(from: .sidebarLeft))
    }

    @Test func readerSettingsGuidanceExplainsImmediateSidebarLayoutChanges() {
        #expect(
            SettingsGuidance.layoutHelpText(selectedMode: .sidebarRight)
                == "Sidebar placement changes immediately."
        )
    }

    @Test func diffBaselineLookbackTimeIntervalValues() {
        #expect(DiffBaselineLookback.tenSeconds.timeInterval == 10)
        #expect(DiffBaselineLookback.thirtySeconds.timeInterval == 30)
        #expect(DiffBaselineLookback.oneMinute.timeInterval == 60)
        #expect(DiffBaselineLookback.twoMinutes.timeInterval == 120)
        #expect(DiffBaselineLookback.fiveMinutes.timeInterval == 300)
        #expect(DiffBaselineLookback.tenMinutes.timeInterval == 600)
    }

    @Test func diffBaselineLookbackDisplayNames() {
        #expect(DiffBaselineLookback.tenSeconds.displayName == "10 seconds")
        #expect(DiffBaselineLookback.thirtySeconds.displayName == "30 seconds")
        #expect(DiffBaselineLookback.oneMinute.displayName == "1 minute")
        #expect(DiffBaselineLookback.twoMinutes.displayName == "2 minutes")
        #expect(DiffBaselineLookback.fiveMinutes.displayName == "5 minutes")
        #expect(DiffBaselineLookback.tenMinutes.displayName == "10 minutes")
    }

    @Test func diffBaselineLookbackCodableRoundTrip() throws {
        for lookback in DiffBaselineLookback.allCases {
            let data = try JSONEncoder().encode(lookback)
            let decoded = try JSONDecoder().decode(DiffBaselineLookback.self, from: data)
            #expect(decoded == lookback)
        }
    }

    @Test func readerSettingsDecodesDefaultLookbackWhenKeyMissing() throws {
        var settingsDict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(Settings.default)
        ) as! [String: Any]
        settingsDict.removeValue(forKey: "diffBaselineLookback")
        let data = try JSONSerialization.data(withJSONObject: settingsDict)

        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded.diffBaselineLookback == .twoMinutes)
    }

    @Test func readerSettingsCodableRoundTripPreservesDiffBaselineLookback() throws {
        var settings = Settings.default
        settings.diffBaselineLookback = .fiveMinutes

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        #expect(decoded.diffBaselineLookback == .fiveMinutes)
    }

    @Test func readerSettingsGuidanceFormatsMarkdownAssociationPermissionErrorWithoutStatusCode() {
        let error = MarkdownAssociationError.launchServicesFailed([
            .init(
                contentType: "net.daringfireball.markdown",
                role: .all,
                status: -54
            )
        ])

        #expect(
            SettingsGuidance.markdownAssociationErrorMessage(for: error)
                == "macOS didn’t allow this change. In Finder, select a .md file, choose Get Info, set Open with to MarkdownObserver, then choose Change All."
        )
    }

    @Test @MainActor func dismissedHintsPersistAcrossReload() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.dismissed-hints.tests"
        let store = SettingsStore(storage: storage, storageKey: storageKey)

        store.dismissHint(.manualGroupReorder)
        store.dismissHint(.changeNavigation)

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.isHintDismissed(.manualGroupReorder))
        #expect(reloadedStore.isHintDismissed(.changeNavigation))
        #expect(!reloadedStore.isHintDismissed(.multiSelect))
    }

    @Test @MainActor func readerSettingsStorePersistsReaderThemeOverride() {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.override.tests"
        let store = SettingsStore(
            storage: storage,
            storageKey: storageKey,
            minimumPersistInterval: 0
        )

        store.updateTheme(.nord)
        store.updateReaderThemeOverride(
            ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: "#AABBCC")
        )

        let reloadedStore = SettingsStore(storage: storage, storageKey: storageKey)
        #expect(reloadedStore.currentSettings.readerThemeOverride?.themeKind == .nord)
        #expect(reloadedStore.currentSettings.readerThemeOverride?.backgroundHex == "#112233")
        #expect(reloadedStore.currentSettings.readerThemeOverride?.foregroundHex == "#AABBCC")
    }

    @Test @MainActor func readerSettingsLegacyPayloadDecodesOverrideAsNil() throws {
        let storage = TestSettingsKeyValueStorage()
        let storageKey = "reader.settings.legacy-override.tests"
        let legacy: [String: Any] = [
            "appAppearance": "system",
            "readerTheme": "nord",
            "syntaxTheme": "monokai",
            "baseFontSize": 15,
            "autoRefreshOnExternalChange": true,
            "notificationsEnabled": true,
            "multiFileDisplayMode": "sidebarLeft",
            "sidebarSortMode": "openOrder",
            "sidebarGroupSortMode": "lastChangedNewestFirst",
            "favoriteWatchedFolders": [],
            "recentWatchedFolders": [],
            "recentManuallyOpenedFiles": [],
            "trustedImageFolders": [],
            "diffBaselineLookback": "twoMinutes",
            "dismissedHints": []
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)
        storage.set(data, forKey: storageKey)

        let store = SettingsStore(storage: storage, storageKey: storageKey)

        #expect(store.currentSettings.readerThemeOverride == nil)
        #expect(store.currentSettings.readerTheme == .nord)
    }
}
