import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderFavoriteWatchedFolderTests {
    // MARK: - Model

    @Test func matchesReturnsTrueForSameFolderPathAndOptions() {
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(entry.matches(folderPath: "/tmp/docs", options: .default))
    }

    @Test func matchesReturnsFalseForDifferentPath() {
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(!entry.matches(folderPath: "/tmp/other", options: .default))
    }

    @Test func matchesReturnsFalseForDifferentOptions() {
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )

        let differentOptions = FolderWatchOptions(
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
            openDocumentFileURLs: [folderURL.appendingPathComponent("guide.md")],
            into: []
        )

        #expect(result.count == 1)
        #expect(result[0].name == "Docs")
        #expect(result[0].openDocumentRelativePaths == ["guide.md"])
    }

    @Test func scopedOpenDocumentRelativePathsFiltersToScopeAndExclusions() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let options = FolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: ["/tmp/docs/excluded"]
        )

        let result = FavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
            from: [
                folderURL.appendingPathComponent("a.md"),
                folderURL.appendingPathComponent("nested/b.md"),
                folderURL.appendingPathComponent("excluded/c.md"),
                URL(fileURLWithPath: "/tmp/outside.md"),
                folderURL.appendingPathComponent("nested/image.png")
            ],
            relativeTo: folderURL,
            options: options
        )

        #expect(result == ["a.md", "nested/b.md"])
    }

    @Test func resolvedOpenDocumentFileURLsIgnoresInvalidRelativePaths() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: folderURL.path,
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
            bookmarkData: nil,
            openDocumentRelativePaths: [
                "a.md",
                "nested/../nested/b.md",
                "../outside.md",
                "/tmp/escape.md",
                ""
            ],
            createdAt: .now
        )

        let resolvedPaths = entry.resolvedOpenDocumentFileURLs(relativeTo: folderURL).map(\.path).sorted()

        #expect(resolvedPaths == ["/tmp/docs/a.md", "/tmp/docs/nested/b.md"])
    }

    @Test func insertingDuplicateFavoriteDoesNotAdd() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs")
        let existing = [FavoriteWatchedFolder(
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
        let existing = [FavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: .default
        )]

        let differentOptions = FolderWatchOptions(
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
            FavoriteWatchedFolder(
                id: id,
                name: "A",
                folderPath: "/tmp/a",
                options: .default,
                bookmarkData: nil,
                createdAt: .now
            ),
            FavoriteWatchedFolder(
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
            FavoriteWatchedFolder(
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
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: .default,
            openDocumentFileURLs: [
                folderURL.appendingPathComponent("guide.md"),
                URL(fileURLWithPath: "/tmp/elsewhere.md")
            ]
        )

        #expect(store.currentSettings.favoriteWatchedFolders.count == 1)
        #expect(store.currentSettings.favoriteWatchedFolders[0].name == "Docs")
        #expect(store.currentSettings.favoriteWatchedFolders[0].openDocumentRelativePaths == ["guide.md"])
        #expect(storage.setCallCount > 0)
    }

    @Test @MainActor func settingsStoreUpdatesFavoriteOpenDocuments() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            openDocumentFileURLs: []
        )

        let entryID = store.currentSettings.favoriteWatchedFolders[0].id
        store.updateFavoriteWatchedFolderOpenDocuments(
            id: entryID,
            folderURL: folderURL,
            openDocumentFileURLs: [
                folderURL.appendingPathComponent("alpha.md"),
                folderURL.appendingPathComponent("nested/beta.md"),
                URL(fileURLWithPath: "/tmp/outside.md")
            ]
        )

        #expect(store.currentSettings.favoriteWatchedFolders[0].openDocumentRelativePaths == ["alpha.md"])
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

        let entry = FavoriteWatchedFolder(
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

        let entry = FavoriteWatchedFolder(
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

        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
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

        let session = FolderWatchSession(
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

        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .includeSubfolders),
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

        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .includeSubfolders),
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
            options: FolderWatchOptions(
                openMode: .openAllMarkdownFiles,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: ["/tmp/project/node_modules"]
            ),
            openDocumentFileURLs: [
                URL(fileURLWithPath: "/tmp/project/README.md"),
                URL(fileURLWithPath: "/tmp/project/docs/guide.md")
            ]
        )

        let reloadedStore = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        #expect(reloadedStore.currentSettings.favoriteWatchedFolders.count == 1)
        let reloaded = reloadedStore.currentSettings.favoriteWatchedFolders[0]
        #expect(reloaded.name == "My Project")
        #expect(reloaded.folderPath == ReaderFileRouting.normalizedFileURL(URL(fileURLWithPath: "/tmp/project")).path)
        #expect(reloaded.options.openMode == .openAllMarkdownFiles)
        #expect(reloaded.options.scope == .includeSubfolders)
        #expect(reloaded.options.excludedSubdirectoryPaths == ["/tmp/project/node_modules"])
        #expect(reloaded.openDocumentRelativePaths == ["README.md", "docs/guide.md"])
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

    @Test func decodingFavoriteWithoutAllKnownRelativePathsDefaultsToEmpty() throws {
        let json = """
        {
            "id": "FDFBD48E-E0AB-4F82-95EB-391C3DF5CF63",
            "name": "Docs",
            "folderPath": "/tmp/docs",
            "options": {
                "openMode": "openAllMarkdownFiles",
                "scope": "selectedFolderOnly"
            },
            "createdAt": 0
        }
        """

        let favorite = try JSONDecoder().decode(FavoriteWatchedFolder.self, from: Data(json.utf8))
        #expect(favorite.allKnownRelativePaths.isEmpty)
    }

    @Test func decodingFavoriteWithoutOpenDocumentRelativePathsDefaultsToEmptyArray() throws {
        let json = """
        {
            "id": "FDFBD48E-E0AB-4F82-95EB-391C3DF5CF63",
            "name": "Docs",
            "folderPath": "/tmp/docs",
            "options": {
                "openMode": "watchChangesOnly",
                "scope": "selectedFolderOnly"
            },
            "createdAt": 0
        }
        """

        let favorite = try JSONDecoder().decode(FavoriteWatchedFolder.self, from: Data(json.utf8))
        #expect(favorite.openDocumentRelativePaths.isEmpty)
    }

    // MARK: - Session excluded paths

    @Test func excludedSubdirectoryRelativePathsComputesCorrectly() {
        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(
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
        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly,
                excludedSubdirectoryPaths: ["/tmp/docs/node_modules"]
            ),
            startedAt: .now
        )

        #expect(session.excludedSubdirectoryRelativePaths.isEmpty)
    }

    @Test func excludedSubdirectoryRelativePathsIgnoresPathsOutsideRoot() {
        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/docs"),
            options: FolderWatchOptions(
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

    // MARK: - Reorder

    @Test func reorderingPreservesOrderByIDs() {
        let a = makeFavorite(name: "A", folderPath: "/tmp/a")
        let b = makeFavorite(name: "B", folderPath: "/tmp/b")
        let c = makeFavorite(name: "C", folderPath: "/tmp/c")

        let result = ReaderFavoriteHistory.reordering(
            ids: [c.id, a.id, b.id],
            in: [a, b, c]
        )

        #expect(result.map(\.name) == ["C", "A", "B"])
    }

    @Test func reorderingAppendsEntriesMissingFromIDs() {
        let a = makeFavorite(name: "A", folderPath: "/tmp/a")
        let b = makeFavorite(name: "B", folderPath: "/tmp/b")
        let c = makeFavorite(name: "C", folderPath: "/tmp/c")

        let result = ReaderFavoriteHistory.reordering(
            ids: [c.id],
            in: [a, b, c]
        )

        #expect(result.count == 3)
        #expect(result[0].name == "C")
        #expect(Set(result.map(\.id)) == Set([a.id, b.id, c.id]))
    }

    @Test func reorderingIgnoresUnknownIDs() {
        let a = makeFavorite(name: "A", folderPath: "/tmp/a")
        let unknownID = UUID()

        let result = ReaderFavoriteHistory.reordering(
            ids: [unknownID, a.id],
            in: [a]
        )

        #expect(result.count == 1)
        #expect(result[0].id == a.id)
    }

    @Test func reorderingWithEmptyIDsReturnsAllEntries() {
        let a = makeFavorite(name: "A", folderPath: "/tmp/a")
        let b = makeFavorite(name: "B", folderPath: "/tmp/b")

        let result = ReaderFavoriteHistory.reordering(
            ids: [],
            in: [a, b]
        )

        #expect(result.count == 2)
    }

    @Test func reorderingWithEmptyEntriesReturnsEmpty() {
        let result = ReaderFavoriteHistory.reordering(
            ids: [UUID()],
            in: []
        )

        #expect(result.isEmpty)
    }

    @Test @MainActor func settingsStoreReordersFavorites() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)

        store.addFavoriteWatchedFolder(name: "A", folderURL: URL(fileURLWithPath: "/tmp/a"), options: .default)
        store.addFavoriteWatchedFolder(name: "B", folderURL: URL(fileURLWithPath: "/tmp/b"), options: .default)
        store.addFavoriteWatchedFolder(name: "C", folderURL: URL(fileURLWithPath: "/tmp/c"), options: .default)

        let ids = store.currentSettings.favoriteWatchedFolders.map(\.id)
        store.reorderFavoriteWatchedFolders(orderedIDs: [ids[2], ids[0], ids[1]])

        let names = store.currentSettings.favoriteWatchedFolders.map(\.name)
        #expect(names == ["C", "A", "B"])
    }

    // MARK: - Excluded Subdirectory Relative Paths (Favorite)

    @Test func excludedSubdirectoryRelativePathsForFavorite() {
        let entry = FavoriteWatchedFolder(
            name: "Test",
            folderPath: "/tmp/project",
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .includeSubfolders,
                excludedSubdirectoryPaths: ["/tmp/project/node_modules", "/tmp/project/.git"]
            ),
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(entry.excludedSubdirectoryRelativePaths == [".git", "node_modules"])
    }

    @Test func excludedSubdirectoryRelativePathsEmptyForSelectedFolderOnly() {
        let entry = FavoriteWatchedFolder(
            name: "Test",
            folderPath: "/tmp/project",
            options: FolderWatchOptions(
                openMode: .watchChangesOnly,
                scope: .selectedFolderOnly,
                excludedSubdirectoryPaths: ["/tmp/project/node_modules"]
            ),
            bookmarkData: nil,
            createdAt: .now
        )

        #expect(entry.excludedSubdirectoryRelativePaths.isEmpty)
    }

    // MARK: - Known documents

    @Test @MainActor func favoriteWithKnownPathsSurvivesRoundTrip() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)
        let folderURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)

        store.addFavoriteWatchedFolder(
            name: "Project",
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            openDocumentFileURLs: [folderURL.appendingPathComponent("README.md")]
        )

        let entryID = store.currentSettings.favoriteWatchedFolders[0].id
        store.updateFavoriteWatchedFolderKnownDocuments(
            id: entryID,
            folderURL: folderURL,
            knownDocumentFileURLs: [
                folderURL.appendingPathComponent("README.md"),
                folderURL.appendingPathComponent("CHANGELOG.md"),
                folderURL.appendingPathComponent("notes.md")
            ]
        )

        let reloaded = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)
        let entry = reloaded.currentSettings.favoriteWatchedFolders[0]
        #expect(entry.allKnownRelativePaths == ["CHANGELOG.md", "README.md", "notes.md"])
    }

    @Test @MainActor func updatingOpenDocumentsGrowsKnownPaths() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            openDocumentFileURLs: []
        )

        let entryID = store.currentSettings.favoriteWatchedFolders[0].id

        store.updateFavoriteWatchedFolderKnownDocuments(
            id: entryID,
            folderURL: folderURL,
            knownDocumentFileURLs: [
                folderURL.appendingPathComponent("a.md"),
                folderURL.appendingPathComponent("b.md")
            ]
        )

        store.updateFavoriteWatchedFolderOpenDocuments(
            id: entryID,
            folderURL: folderURL,
            openDocumentFileURLs: [
                folderURL.appendingPathComponent("a.md"),
                folderURL.appendingPathComponent("c.md")
            ]
        )

        let entry = store.currentSettings.favoriteWatchedFolders[0]
        #expect(entry.openDocumentRelativePaths == ["a.md", "c.md"])
        #expect(entry.allKnownRelativePaths == ["a.md", "b.md", "c.md"])
    }

    @Test @MainActor func closingFileKeepsItInKnownSetAcrossSyncCycles() {
        let storage = TestSettingsKeyValueStorage()
        let store = ReaderSettingsStore(storage: storage, minimumPersistInterval: 0)
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: folderURL,
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            openDocumentFileURLs: []
        )

        let entryID = store.currentSettings.favoriteWatchedFolders[0].id

        // Simulate initial scan setting known paths
        store.updateFavoriteWatchedFolderKnownDocuments(
            id: entryID,
            folderURL: folderURL,
            knownDocumentFileURLs: [
                folderURL.appendingPathComponent("a.md"),
                folderURL.appendingPathComponent("b.md"),
                folderURL.appendingPathComponent("c.md")
            ]
        )

        // User has a.md and b.md open, then closes b.md
        store.updateFavoriteWatchedFolderOpenDocuments(
            id: entryID,
            folderURL: folderURL,
            openDocumentFileURLs: [folderURL.appendingPathComponent("a.md")]
        )

        let entry = store.currentSettings.favoriteWatchedFolders[0]
        #expect(entry.openDocumentRelativePaths == ["a.md"])
        // b.md and c.md still known even though not open
        #expect(entry.allKnownRelativePaths == ["a.md", "b.md", "c.md"])
    }

    // MARK: - New file discovery

    @Test func newFilesAreThoseNotInKnownSet() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: folderURL.path,
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            bookmarkData: nil,
            openDocumentRelativePaths: ["a.md", "b.md"],
            allKnownRelativePaths: ["a.md", "b.md", "c.md"],
            createdAt: .now
        )

        let scannedURLs = [
            folderURL.appendingPathComponent("a.md"),
            folderURL.appendingPathComponent("b.md"),
            folderURL.appendingPathComponent("c.md"),
            folderURL.appendingPathComponent("d.md"),
            folderURL.appendingPathComponent("e.md")
        ]

        let newURLs = entry.newFileURLs(fromScanned: scannedURLs, relativeTo: folderURL)
        #expect(newURLs.map(\.lastPathComponent).sorted() == ["d.md", "e.md"])
    }

    @Test func emptyKnownSetTreatsAllScannedFilesAsNew() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: folderURL.path,
            options: FolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly),
            bookmarkData: nil,
            openDocumentRelativePaths: [],
            allKnownRelativePaths: [],
            createdAt: .now
        )

        let scannedURLs = [
            folderURL.appendingPathComponent("a.md"),
            folderURL.appendingPathComponent("b.md")
        ]

        let newURLs = entry.newFileURLs(fromScanned: scannedURLs, relativeTo: folderURL)
        #expect(newURLs.count == 2)
    }

    @Test func watchChangesOnlyFavoriteDoesNotDiscoverNewFiles() {
        let entry = FavoriteWatchedFolder(
            name: "Docs",
            folderPath: "/tmp/docs",
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            bookmarkData: nil,
            openDocumentRelativePaths: [],
            allKnownRelativePaths: [],
            createdAt: .now
        )

        let shouldDiscover = entry.options.openMode == .openAllMarkdownFiles
        #expect(!shouldDiscover)
    }

    // MARK: - Workspace state migration

    @Test func decodingFavoriteWithoutWorkspaceStateProducesValidDefaults() throws {
        let json = """
        {
            "id": "FDFBD48E-E0AB-4F82-95EB-391C3DF5CF63",
            "name": "Legacy Favorite",
            "folderPath": "/tmp/legacy",
            "options": {
                "openMode": "openAllMarkdownFiles",
                "scope": "selectedFolderOnly"
            },
            "openDocumentRelativePaths": ["readme.md"],
            "allKnownRelativePaths": ["readme.md", "notes.md"],
            "createdAt": 0
        }
        """

        let favorite = try JSONDecoder().decode(FavoriteWatchedFolder.self, from: Data(json.utf8))

        #expect(favorite.name == "Legacy Favorite")
        #expect(favorite.openDocumentRelativePaths == ["readme.md"])

        let expectedDefault = FavoriteWorkspaceState.from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: FavoriteWorkspaceState.defaultSidebarWidth
        )
        #expect(favorite.workspaceState == expectedDefault)
        #expect(favorite.workspaceState.pinnedGroupIDs.isEmpty)
        #expect(favorite.workspaceState.collapsedGroupIDs.isEmpty)
        #expect(favorite.workspaceState.sidebarWidth == FavoriteWorkspaceState.defaultSidebarWidth)
    }

    @Test func encodingAndDecodingPreservesWorkspaceState() throws {
        let customState = FavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 320,
            pinnedGroupIDs: ["group-1", "group-2"],
            collapsedGroupIDs: ["group-3"]
        )

        let original = FavoriteWatchedFolder(
            name: "Workspace Test",
            folderPath: "/tmp/workspace",
            options: .default,
            bookmarkData: nil,
            workspaceState: customState,
            createdAt: .now
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FavoriteWatchedFolder.self, from: data)

        #expect(decoded.workspaceState == customState)
        #expect(decoded.workspaceState.fileSortMode == .nameAscending)
        #expect(decoded.workspaceState.groupSortMode == .lastChangedNewestFirst)
        #expect(decoded.workspaceState.sidebarPosition == .sidebarRight)
        #expect(decoded.workspaceState.sidebarWidth == 320)
        #expect(decoded.workspaceState.pinnedGroupIDs == ["group-1", "group-2"])
        #expect(decoded.workspaceState.collapsedGroupIDs == ["group-3"])
    }

    // MARK: - Deleted file filtering (#278)

    @Test func existingOpenDocumentFileURLsExcludesDeletedFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimarkTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingFile = tempDir.appendingPathComponent("exists.md")
        try Data("# Exists".utf8).write(to: existingFile)

        let entry = FavoriteWatchedFolder(
            name: "Test",
            folderPath: tempDir.path,
            options: FolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            bookmarkData: nil,
            openDocumentRelativePaths: ["exists.md", "deleted.md"],
            createdAt: .now
        )

        let allResolved = entry.resolvedOpenDocumentFileURLs(relativeTo: tempDir)
        #expect(allResolved.count == 2, "Unfiltered method returns both existing and deleted paths")

        let existingOnly = entry.existingOpenDocumentFileURLs(relativeTo: tempDir)
        #expect(existingOnly.count == 1)
        #expect(existingOnly[0].lastPathComponent == "exists.md")
    }

    // MARK: - Helpers

    private func makeFavorite(name: String, folderPath: String) -> FavoriteWatchedFolder {
        FavoriteWatchedFolder(
            name: name,
            folderPath: folderPath,
            options: .default,
            bookmarkData: nil,
            createdAt: .now
        )
    }
}
