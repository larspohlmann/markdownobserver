import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct TrustedImageFoldersStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        private(set) var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(
        initial: [TrustedImageFolder] = [],
        resolver: @escaping BookmarkRefreshing.Resolver = { _ in (URL(fileURLWithPath: "/ignored"), false) },
        creator: @escaping BookmarkRefreshing.Creator = { _ in Data() }
    ) -> (TrustedImageFoldersStore, RecordingCoordinator) {
        let helper = BookmarkRefreshing(resolve: resolver, create: creator)
        let store = TrustedImageFoldersStore(initial: initial, bookmarkRefreshing: helper)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func addInsertsUniqueFolder() {
        let (store, coordinator) = makeStore()

        store.addTrustedImageFolder(URL(fileURLWithPath: "/tmp/images", isDirectory: true))

        #expect(store.currentTrustedFolders.count == 1)
        #expect(coordinator.coalescingCalls == [false])
    }

    @Test @MainActor func resolvedURLReturnsNilWhenNoFolderContainsFile() {
        let entry = TrustedImageFolder(
            folderPath: "/tmp/images",
            bookmarkData: Data([0x01])
        )
        let (store, _) = makeStore(initial: [entry])

        let result = store.resolvedTrustedImageFolderURL(containing: URL(fileURLWithPath: "/elsewhere/a.png"))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLReturnsNilWhenEntryHasNoBookmark() {
        let entry = TrustedImageFolder(folderPath: "/tmp/images", bookmarkData: nil)
        let (store, _) = makeStore(initial: [entry])

        let result = store.resolvedTrustedImageFolderURL(containing: URL(fileURLWithPath: "/tmp/images/a.png"))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLRefreshesStaleBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/images", isDirectory: true)
        let refreshed = Data([0xCC])
        let entry = TrustedImageFolder(folderPath: folderURL.path, bookmarkData: Data([0x01]))
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in (folderURL, true) },
            creator: { _ in refreshed }
        )

        let result = store.resolvedTrustedImageFolderURL(containing: URL(fileURLWithPath: "/tmp/images/a.png"))

        #expect(result == folderURL)
        #expect(store.currentTrustedFolders.first?.bookmarkData == refreshed)
    }

    @Test @MainActor func resolvedURLClearsInvalidBookmarkAndReturnsNil() {
        let entry = TrustedImageFolder(folderPath: "/tmp/images", bookmarkData: Data([0x01]))
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let result = store.resolvedTrustedImageFolderURL(containing: URL(fileURLWithPath: "/tmp/images/a.png"))

        #expect(result == nil)
        #expect(store.currentTrustedFolders.first?.bookmarkData == nil)
    }
}
