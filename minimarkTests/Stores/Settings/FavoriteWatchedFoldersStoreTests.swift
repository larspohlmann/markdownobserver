import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FavoriteWatchedFoldersStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(
        initial: [ReaderFavoriteWatchedFolder] = [],
        resolver: @escaping BookmarkRefreshing.Resolver = { _ in (URL(fileURLWithPath: "/ignored"), false) },
        creator: @escaping BookmarkRefreshing.Creator = { _ in Data() }
    ) -> (FavoriteWatchedFoldersStore, RecordingCoordinator) {
        let helper = BookmarkRefreshing(resolve: resolver, create: creator)
        let store = FavoriteWatchedFoldersStore(initial: initial, bookmarkRefreshing: helper)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func addAppendsUniqueFavoriteAndNotifiesCoordinatorImmediately() {
        let (store, coordinator) = makeStore()

        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )

        #expect(store.currentFavorites.count == 1)
        #expect(store.currentFavorites.first?.name == "Docs")
        #expect(coordinator.coalescingCalls == [false])
    }

    @Test @MainActor func addDuplicateFavoriteIsNoOp() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let (store, coordinator) = makeStore()
        store.addFavoriteWatchedFolder(name: "Docs", folderURL: folderURL, options: .default)
        coordinator.coalescingCalls.removeAll()

        store.addFavoriteWatchedFolder(name: "Docs again", folderURL: folderURL, options: .default)

        #expect(store.currentFavorites.count == 1)
        #expect(coordinator.coalescingCalls.isEmpty)
    }

    @Test @MainActor func removeFavoriteByID() {
        let (store, coordinator) = makeStore()
        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )
        let id = store.currentFavorites[0].id
        coordinator.coalescingCalls.removeAll()

        store.removeFavoriteWatchedFolder(id: id)

        #expect(store.currentFavorites.isEmpty)
        #expect(coordinator.coalescingCalls == [false])
    }

    @Test @MainActor func renameFavorite() {
        let (store, _) = makeStore()
        store.addFavoriteWatchedFolder(
            name: "Old",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )
        let id = store.currentFavorites[0].id

        store.renameFavoriteWatchedFolder(id: id, newName: "New")

        #expect(store.currentFavorites.first?.name == "New")
    }

    @Test @MainActor func clearFavorites() {
        let (store, _) = makeStore()
        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )

        store.clearFavoriteWatchedFolders()

        #expect(store.currentFavorites.isEmpty)
    }

    @Test @MainActor func updateFavoriteWorkspaceStateUsesCoalescedPersistence() {
        let (store, coordinator) = makeStore()
        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )
        let id = store.currentFavorites[0].id
        coordinator.coalescingCalls.removeAll()

        let newState = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .nameAscending,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 280,
            pinnedGroupIDs: [],
            collapsedGroupIDs: []
        )
        store.updateFavoriteWorkspaceState(id: id, workspaceState: newState)

        #expect(store.currentFavorites.first?.workspaceState == newState)
        #expect(coordinator.coalescingCalls == [true])
    }

    @Test @MainActor func updateIdenticalWorkspaceStateSkipsNotification() {
        let (store, coordinator) = makeStore()
        store.addFavoriteWatchedFolder(
            name: "Docs",
            folderURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true),
            options: .default
        )
        let existing = store.currentFavorites[0]
        coordinator.coalescingCalls.removeAll()

        store.updateFavoriteWorkspaceState(id: existing.id, workspaceState: existing.workspaceState)

        #expect(coordinator.coalescingCalls.isEmpty)
    }

    @Test @MainActor func resolvedFavoriteWatchedFolderURLReturnsFolderURLWhenNoBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let entry = ReaderFavoriteWatchedFolder(name: "Docs", folderURL: folderURL, options: .default)
        let (store, _) = makeStore(initial: [entry])

        let resolved = store.resolvedFavoriteWatchedFolderURL(for: entry)

        #expect(resolved == entry.folderURL)
    }

    @Test @MainActor func resolvedFavoriteWatchedFolderURLRefreshesStaleBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let resolvedURL = URL(fileURLWithPath: "/tmp/docs-moved", isDirectory: true)
        let originalBookmark = Data([0x01])
        let refreshedBookmark = Data([0x02, 0x03])
        let entry = ReaderFavoriteWatchedFolder(
            id: UUID(),
            name: "Docs",
            folderPath: folderURL.path,
            options: .default,
            bookmarkData: originalBookmark,
            openDocumentRelativePaths: [],
            allKnownRelativePaths: [],
            workspaceState: .from(
                settings: .default,
                pinnedGroupIDs: [],
                collapsedGroupIDs: [],
                sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
            ),
            createdAt: Date()
        )
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in (resolvedURL, true) },
            creator: { _ in refreshedBookmark }
        )

        let result = store.resolvedFavoriteWatchedFolderURL(for: entry)

        #expect(result == resolvedURL)
        #expect(store.currentFavorites.first?.bookmarkData == refreshedBookmark)
        #expect(store.currentFavorites.first?.folderPath == resolvedURL.path)
    }

    @Test @MainActor func resolvedFavoriteWatchedFolderURLClearsInvalidBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)
        let entry = ReaderFavoriteWatchedFolder(
            id: UUID(),
            name: "Docs",
            folderPath: folderURL.path,
            options: .default,
            bookmarkData: Data([0x01]),
            openDocumentRelativePaths: [],
            allKnownRelativePaths: [],
            workspaceState: .from(
                settings: .default,
                pinnedGroupIDs: [],
                collapsedGroupIDs: [],
                sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
            ),
            createdAt: Date()
        )
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let result = store.resolvedFavoriteWatchedFolderURL(for: entry)

        #expect(result == entry.folderURL)
        #expect(store.currentFavorites.first?.bookmarkData == nil)
    }
}
