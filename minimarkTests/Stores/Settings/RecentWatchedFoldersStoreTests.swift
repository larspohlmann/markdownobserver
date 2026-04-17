import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct RecentWatchedFoldersStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        private(set) var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(
        initial: [ReaderRecentWatchedFolder] = [],
        resolver: @escaping BookmarkRefreshing.Resolver = { _ in (URL(fileURLWithPath: "/ignored"), false) },
        creator: @escaping BookmarkRefreshing.Creator = { _ in Data() }
    ) -> (RecentWatchedFoldersStore, RecordingCoordinator) {
        let helper = BookmarkRefreshing(resolve: resolver, create: creator)
        let store = RecentWatchedFoldersStore(initial: initial, bookmarkRefreshing: helper)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func addInsertsUniqueEntryAtFrontImmediately() {
        let (store, coordinator) = makeStore()

        store.addRecentWatchedFolder(URL(fileURLWithPath: "/tmp/a", isDirectory: true), options: .default)
        store.addRecentWatchedFolder(URL(fileURLWithPath: "/tmp/b", isDirectory: true), options: .default)

        #expect(store.currentRecentWatchedFolders.map(\.folderPath).prefix(2) == ["/tmp/b", "/tmp/a"])
        #expect(coordinator.coalescingCalls == [false, false])
    }

    @Test @MainActor func addRespectsMaximumCount() {
        let (store, _) = makeStore()
        for i in 0..<(ReaderRecentWatchedFolder.maximumCount + 5) {
            store.addRecentWatchedFolder(
                URL(fileURLWithPath: "/tmp/f-\(i)", isDirectory: true),
                options: .default
            )
        }

        #expect(store.currentRecentWatchedFolders.count == ReaderRecentWatchedFolder.maximumCount)
    }

    @Test @MainActor func clearEmptiesCollection() {
        let (store, _) = makeStore()
        store.addRecentWatchedFolder(URL(fileURLWithPath: "/tmp/a", isDirectory: true), options: .default)

        store.clearRecentWatchedFolders()

        #expect(store.currentRecentWatchedFolders.isEmpty)
    }

    @Test @MainActor func resolvedURLReturnsNilWhenFolderNotInHistory() {
        let (store, _) = makeStore()

        let result = store.resolvedRecentWatchedFolderURL(matching: URL(fileURLWithPath: "/tmp/missing", isDirectory: true))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLRefreshesStaleBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/stale", isDirectory: true)
        let entry = ReaderRecentWatchedFolder(
            folderPath: folderURL.path,
            options: .default,
            bookmarkData: Data([0x01])
        )
        let refreshed = Data([0xAA])
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in (folderURL, true) },
            creator: { _ in refreshed }
        )

        let result = store.resolvedRecentWatchedFolderURL(matching: folderURL)

        #expect(result == folderURL)
        #expect(store.currentRecentWatchedFolders.first?.bookmarkData == refreshed)
    }

    @Test @MainActor func resolvedURLClearsInvalidBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/broken", isDirectory: true)
        let entry = ReaderRecentWatchedFolder(
            folderPath: folderURL.path,
            options: .default,
            bookmarkData: Data([0x01])
        )
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let result = store.resolvedRecentWatchedFolderURL(matching: folderURL)

        #expect(result?.path == folderURL.path)
        #expect(store.currentRecentWatchedFolders.first?.bookmarkData == nil)
    }
}
