import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct RecentOpenedFilesStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        private(set) var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(
        initial: [RecentOpenedFile] = [],
        resolver: @escaping BookmarkRefreshing.Resolver = { _ in (URL(fileURLWithPath: "/ignored"), false) },
        creator: @escaping BookmarkRefreshing.Creator = { _ in Data() }
    ) -> (RecentOpenedFilesStore, RecordingCoordinator) {
        let helper = BookmarkRefreshing(resolve: resolver, create: creator)
        let store = RecentOpenedFilesStore(initial: initial, bookmarkRefreshing: helper)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func addInsertsUniqueEntryAtFront() {
        let (store, coordinator) = makeStore()

        store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/a.md"))
        store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/b.md"))

        #expect(store.currentRecentOpenedFiles.map(\.filePath).prefix(2) == ["/tmp/b.md", "/tmp/a.md"])
        #expect(coordinator.coalescingCalls == [false, false])
    }

    @Test @MainActor func addRespectsMaximumCount() {
        let (store, _) = makeStore()
        for i in 0..<(RecentOpenedFile.maximumCount + 3) {
            store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/f-\(i).md"))
        }

        #expect(store.currentRecentOpenedFiles.count == RecentOpenedFile.maximumCount)
    }

    @Test @MainActor func clearEmptiesCollection() {
        let (store, _) = makeStore()
        store.addRecentManuallyOpenedFile(URL(fileURLWithPath: "/tmp/a.md"))

        store.clearRecentManuallyOpenedFiles()

        #expect(store.currentRecentOpenedFiles.isEmpty)
    }

    @Test @MainActor func resolvedURLReturnsNilWhenFileNotInHistory() {
        let (store, _) = makeStore()

        let result = store.resolvedRecentManuallyOpenedFileURL(matching: URL(fileURLWithPath: "/tmp/missing.md"))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLRefreshesStaleBookmark() {
        let fileURL = URL(fileURLWithPath: "/tmp/stale.md")
        let entry = RecentOpenedFile(filePath: fileURL.path, bookmarkData: Data([0x01]))
        let refreshed = Data([0xBB])
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in (fileURL, true) },
            creator: { _ in refreshed }
        )

        let result = store.resolvedRecentManuallyOpenedFileURL(matching: fileURL)

        #expect(result == fileURL)
        #expect(store.currentRecentOpenedFiles.first?.bookmarkData == refreshed)
    }

    @Test @MainActor func resolvedURLClearsInvalidBookmark() {
        let fileURL = URL(fileURLWithPath: "/tmp/broken.md")
        let entry = RecentOpenedFile(filePath: fileURL.path, bookmarkData: Data([0x01]))
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let result = store.resolvedRecentManuallyOpenedFileURL(matching: fileURL)

        #expect(result?.path == fileURL.path)
        #expect(store.currentRecentOpenedFiles.first?.bookmarkData == nil)
    }
}
