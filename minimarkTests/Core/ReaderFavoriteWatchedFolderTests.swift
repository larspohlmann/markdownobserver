import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderFavoriteWatchedFolderTests {
    // MARK: - Model

    @Test func matchesReturnsTrueForSameFolderPathAndOptions() {
        let entry = ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(entry.matches(folderPath: "/tmp/docs", options: .default))
    }

    @Test func matchesReturnsFalseForDifferentPath() {
        let entry = ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(!entry.matches(folderPath: "/tmp/other", options: .default))
    }

    @Test func matchesReturnsFalseForDifferentOptions() {
        let entry = ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        let differentOptions = ReaderFolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders
        )
        #expect(!entry.matches(folderPath: "/tmp/docs", options: differentOptions))
    }

    // MARK: - Insert

    @Test func insertingUniqueFavoriteAppendsNewEntry() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs")
        let result = ReaderFavoriteHistory.insertingUniqueFavorite(
            name: "Docs",
            folderURL: folderURL,
            options: .default,
            into: []
        )

        #expect(result.count == 1)
        #expect(result[0].name == "Docs")
    }

    @Test func insertingDuplicateFavoriteDoesNotAdd() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs")
        let existing = [ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: .default
        )]

        let result = ReaderFavoriteHistory.insertingUniqueFavorite(
            name: "Docs Again",
            folderURL: folderURL,
            options: .default,
            into: existing
        )

        #expect(result.count == 1)
        #expect(result[0].name == "Docs")
    }

    @Test func insertingSameFolderWithDifferentOptionsAddsNewEntry() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs")
        let existing = [ReaderFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: .default
        )]

        let differentOptions = ReaderFolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders
        )

        let result = ReaderFavoriteHistory.insertingUniqueFavorite(
            name: "Docs (subfolders)",
            folderURL: folderURL,
            options: differentOptions,
            into: existing
        )

        #expect(result.count == 2)
    }

    // MARK: - Remove

    @Test func removingFavoriteByIDRemovesCorrectEntry() {
        let id = UUID()
        let entries = [
            ReaderFavoriteWatchedFolder(
                id: id,
                name: "A",
                folderPath: "/tmp/a",
                options: .default,
                bookmarkData: nil,
                createdAt: .now
            ),
            ReaderFavoriteWatchedFolder(
                id: UUID(),
                name: "B",
                folderPath: "/tmp/b",
                options: .default,
                bookmarkData: nil,
                createdAt: .now
            )
        ]

        let result = ReaderFavoriteHistory.removingFavorite(id: id, from: entries)

        #expect(result.count == 1)
        #expect(result[0].name == "B")
    }

    // MARK: - Rename

    @Test func renamingFavoriteUpdatesName() {
        let id = UUID()
        let entries = [
            ReaderFavoriteWatchedFolder(
                id: id,
                name: "Old Name",
                folderPath: "/tmp/docs",
                options: .default,
                bookmarkData: nil,
                createdAt: .now
            )
        ]

        let result = ReaderFavoriteHistory.renamingFavorite(id: id, newName: "New Name", in: entries)

        #expect(result[0].name == "New Name")
        #expect(result[0].id == id)
    }

    // MARK: - Settings Store

    @Test @MainActor func settingsStoreAddsFavoriteAndPersists() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: .default
        )

        #expect(store.currentSettings.favoriteWatchedFolders.count == 1)
        #expect(store.currentSettings.favoriteWatchedFolders[0].name == "Docs")
        #expect(storage.setCallCount > 0)
    }

    @Test @MainActor func settingsStoreRemovesFavorite() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: .default
        )

        let id = store.currentSettings.favoriteWatchedFolders[0].id
        store.removeFavoriteWatchedFolder(id: id)

        #expect(store.currentSettings.favoriteWatchedFolders.isEmpty)
    }

    @Test @MainActor func settingsStoreRenamesFavorite() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "Old",
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: .default
        )

        let id = store.currentSettings.favoriteWatchedFolders[0].id
        store.renameFavoriteWatchedFolder(id: id, newName: "New")

        #expect(store.currentSettings.favoriteWatchedFolders[0].name == "New")
    }

    @Test @MainActor func settingsStoreClearsFavorites() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "A",
            folderURL: URL(fileURLWithPath: "/tmp/a"),
            options: .default
        )
        store.addFavoriteWatchedFolder(
            name: "B",
            folderURL: URL(fileURLWithPath: "/tmp/b"),
            options: .default
        )

        store.clearFavoriteWatchedFolders()

        #expect(store.currentSettings.favoriteWatchedFolders.isEmpty)
    }

    @Test @MainActor func settingsStoreResolvesFavoriteBookmark() {
        let storage = TestSettingsKeyValueStorage()
        let resolvedURL = URL(fileURLWithPath: "/tmp/resolved")
        let store = ReaderSettingsStore(
            storage: storage,
            bookmarkResolver: { _ in (resolvedURL, false) },
            bookmarkCreator: { _ in Data([0xAB]) },
            minimumPersistInterval: 0
        )

        let entry = ReaderFavoriteWatchedFolder(
            name: "Test",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: Data([0x01]),
            createdAt: .now
        )

        let result = store.resolvedFavoriteWatchedFolderURL(for: entry)

        #expect(result == resolvedURL)
    }

    @Test @MainActor func settingsStoreReturnsEntryURLWhenBookmarkIsNil() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        let entry = ReaderFavoriteWatchedFolder(
            name: "Test",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        let result = store.resolvedFavoriteWatchedFolderURL(for: entry)

        #expect(result == URL(fileURLWithPath: "/tmp/docs"))
    }

    // MARK: - Save/remove using session + settings store (regression: session lives at window level)

    @Test @MainActor func saveFavoriteUsingSessionAndSettingsStoreDirectly() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
            startedAt: .now
        )

        store.addFavoriteWatchedFolder(
            name: "My Docs",
            folderURL: session.folderURL,
            options: session.options
        )

        #expect(store.currentSettings.favoriteWatchedFolders.count == 1)
        #expect(store.currentSettings.favoriteWatchedFolders[0].name == "My Docs")
        #expect(store.currentSettings.favoriteWatchedFolders[0].options == session.options)
    }

    @Test @MainActor func removeFavoriteMatchingSessionByPathAndOptions() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: .default,
            startedAt: .now
        )

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: session.folderURL,
            options: session.options
        )
        #expect(store.currentSettings.favoriteWatchedFolders.count == 1)

        let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
        let match = store.currentSettings.favoriteWatchedFolders.first {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
        #expect(match != nil)

        store.removeFavoriteWatchedFolder(id: match!.id)
        #expect(store.currentSettings.favoriteWatchedFolders.isEmpty)
    }

    @Test @MainActor func isFavoriteCheckMatchesSessionPathAndOptions() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
            startedAt: .now
        )

        let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
        let isFavoriteBefore = store.currentSettings.favoriteWatchedFolders.contains {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
        #expect(!isFavoriteBefore)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: session.folderURL,
            options: session.options
        )

        let isFavoriteAfter = store.currentSettings.favoriteWatchedFolders.contains {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
        #expect(isFavoriteAfter)
    }

    @Test @MainActor func isFavoriteCheckReturnsFalseForDifferentOptions() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: .default
        )

        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders),
            startedAt: .now
        )

        let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
        let isFavorite = store.currentSettings.favoriteWatchedFolders.contains {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
        #expect(!isFavorite)
    }

    // MARK: - Persistence round-trip

    @Test @MainActor func favoriteSurvivesSettingsRoundTrip() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(
            name: "My Project",
            folderURL: URL(fileURLWithPath: "/tmp/project"),
            options: ReaderFolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: ["/tmp/project/node_modules"]
            )
        )

        let reloadedStore = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        #expect(reloadedStore.currentSettings.favoriteWatchedFolders.count == 1)
        let reloaded = reloadedStore.currentSettings.favoriteWatchedFolders[0]
        #expect(reloaded.name == "My Project")
        #expect(reloaded.folderPath == ReaderFileRouting.normalizedFileURL(URL(fileURLWithPath: "/tmp/project")).path)
        #expect(reloaded.options.openMode == .openAllMarkdownFiles)
        #expect(reloaded.options.scope == .includeSubfolders)
        #expect(reloaded.options.excludedSubdirectoryPaths == ["/tmp/project/node_modules"])
    }

    // MARK: - Codable compatibility

    @Test func decodingSettingsWithoutFavoritesFieldDefaultsToEmptyArray() throws {
        let json = """
        {
            "readerTheme": "blackOnWhite",
            "syntaxTheme": "monokai",
            "baseFontSize": 15,
            "autoRefreshOnExternalChange": true,
            "multiFileDisplayMode": "sidebarLeft"
        }
        """

        let settings = try JSONDecoder().decode(ReaderSettings.self, from: Data(json.utf8))
        #expect(settings.favoriteWatchedFolders.isEmpty)
    }

    // MARK: - Session excluded paths

    @Test func excludedSubdirectoryRelativePathsComputesCorrectly() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: [
                    "/tmp/docs/node_modules",
                    "/tmp/docs/build/output"
                ]
            ),
            startedAt: .now
        )

        #expect(session.excludedSubdirectoryRelativePaths == ["build/output", "node_modules"])
    }

    @Test func excludedSubdirectoryRelativePathsEmptyForSelectedFolderScope() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly,
                excludedSubdirectoryPaths: ["/tmp/docs/node_modules"]
            ),
            startedAt: .now
        )

        #expect(session.excludedSubdirectoryRelativePaths.isEmpty)
    }

    @Test func excludedSubdirectoryRelativePathsIgnoresPathsOutsideRoot() {
        let session = ReaderFolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: ReaderFolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: [
                    "/tmp/docs/valid",
                    "/other/outside"
                ]
            ),
            startedAt: .now
        )

        #expect(session.excludedSubdirectoryRelativePaths == ["valid"])
    }
}
