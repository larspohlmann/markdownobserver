import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct LinkAccessGrantsStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        private(set) var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(
        initial: [LinkAccessGrant] = [],
        resolver: @escaping BookmarkRefreshing.Resolver = { _ in (URL(fileURLWithPath: "/ignored"), false) },
        creator: @escaping BookmarkRefreshing.Creator = { _ in Data() }
    ) -> (LinkAccessGrantsStore, RecordingCoordinator) {
        let helper = BookmarkRefreshing(resolve: resolver, create: creator)
        let store = LinkAccessGrantsStore(initial: initial, bookmarkRefreshing: helper)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func addInsertsUniqueFolder() {
        let (store, coordinator) = makeStore()

        store.addLinkAccessGrant(URL(fileURLWithPath: "/tmp/notes", isDirectory: true))

        #expect(store.currentGrants.count == 1)
        #expect(coordinator.coalescingCalls == [false])
    }

    @Test @MainActor func addingSameFolderTwiceKeepsOneEntry() {
        let (store, _) = makeStore()
        let folderURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)

        store.addLinkAccessGrant(folderURL)
        store.addLinkAccessGrant(folderURL)

        #expect(store.currentGrants.count == 1)
    }

    @Test @MainActor func resolvedURLReturnsNilWhenNoGrantContainsFile() {
        let entry = LinkAccessGrant(folderPath: "/tmp/notes", bookmarkData: Data([0x01]))
        let (store, _) = makeStore(initial: [entry])

        let result = store.resolvedLinkAccessFolderURL(containing: URL(fileURLWithPath: "/elsewhere/a.md"))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLReturnsNilWhenEntryHasNoBookmark() {
        let entry = LinkAccessGrant(folderPath: "/tmp/notes", bookmarkData: nil)
        let (store, _) = makeStore(initial: [entry])

        let result = store.resolvedLinkAccessFolderURL(containing: URL(fileURLWithPath: "/tmp/notes/a.md"))

        #expect(result == nil)
    }

    @Test @MainActor func resolvedURLRefreshesStaleBookmark() {
        let folderURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        let refreshed = Data([0xCC])
        let entry = LinkAccessGrant(folderPath: folderURL.path, bookmarkData: Data([0x01]))
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in (folderURL, true) },
            creator: { _ in refreshed }
        )

        let result = store.resolvedLinkAccessFolderURL(containing: URL(fileURLWithPath: "/tmp/notes/a.md"))

        #expect(result == folderURL)
        #expect(store.currentGrants.first?.bookmarkData == refreshed)
    }

    @Test @MainActor func resolvedURLClearsInvalidBookmarkAndReturnsNil() {
        let entry = LinkAccessGrant(folderPath: "/tmp/notes", bookmarkData: Data([0x01]))
        let (store, _) = makeStore(
            initial: [entry],
            resolver: { _ in throw NSError(domain: "test", code: 1) }
        )

        let result = store.resolvedLinkAccessFolderURL(containing: URL(fileURLWithPath: "/tmp/notes/a.md"))

        #expect(result == nil)
        #expect(store.currentGrants.first?.bookmarkData == nil)
    }

    @Test @MainActor func resolvedURLPicksDeepestCoveringFolder() {
        // Both /tmp/notes and /tmp/notes/sub cover the file, but the deeper
        // grant should win so nested authorizations take precedence.
        let outerURL = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
        let innerURL = URL(fileURLWithPath: "/tmp/notes/sub", isDirectory: true)
        let outer = LinkAccessGrant(folderPath: outerURL.path, bookmarkData: Data([0x01]))
        let inner = LinkAccessGrant(folderPath: innerURL.path, bookmarkData: Data([0x02]))

        // Resolver echoes back the URL it would resolve from the bookmark
        // data so we can assert which entry was picked.
        let (store, _) = makeStore(
            initial: [outer, inner],
            resolver: { data in
                if data == Data([0x01]) { return (outerURL, false) }
                if data == Data([0x02]) { return (innerURL, false) }
                throw NSError(domain: "test", code: -1)
            }
        )

        let result = store.resolvedLinkAccessFolderURL(containing: URL(fileURLWithPath: "/tmp/notes/sub/file.md"))

        #expect(result == innerURL)
    }

    @Test @MainActor func clearRemovesAllEntries() {
        let entry = LinkAccessGrant(folderPath: "/tmp/notes", bookmarkData: Data([0x01]))
        let (store, _) = makeStore(initial: [entry])

        store.clearLinkAccessGrants()

        #expect(store.currentGrants.isEmpty)
    }

    @Test @MainActor func insertingUniqueCapsAtMaximum() {
        // Direct test of the history helper's cap, independent of the store.
        var entries: [LinkAccessGrant] = []
        for index in 0..<(LinkAccessGrant.maximumCount + 5) {
            entries = LinkAccessGrantHistory.insertingUnique(
                URL(fileURLWithPath: "/tmp/folder-\(index)", isDirectory: true),
                into: entries
            )
        }

        #expect(entries.count == LinkAccessGrant.maximumCount)
    }
}
