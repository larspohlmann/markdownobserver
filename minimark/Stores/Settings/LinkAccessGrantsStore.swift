import Foundation
import Combine
import Observation

@MainActor @Observable final class LinkAccessGrantsStore: LinkAccessGrantWriting {
    private(set) var currentGrants: [LinkAccessGrant]

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<[LinkAccessGrant], Never>

    @ObservationIgnored
    private let bookmarkRefreshing: BookmarkRefreshing

    var grantsPublisher: AnyPublisher<[LinkAccessGrant], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: [LinkAccessGrant], bookmarkRefreshing: BookmarkRefreshing) {
        self.currentGrants = initial
        self.subject = CurrentValueSubject(initial)
        self.bookmarkRefreshing = bookmarkRefreshing
    }

    func addLinkAccessGrant(_ folderURL: URL) {
        mutate(coalescePersistence: false) { entries in
            entries = LinkAccessGrantHistory.insertingUnique(folderURL, into: entries)
        }
    }

    func resolvedLinkAccessFolderURL(containing fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let filePath = normalizedFileURL.path

        // Prefer the deepest (most specific) covering folder so that nested
        // grants take precedence over their ancestors.
        let coveringEntries = currentGrants
            .filter { entry in
                let folderPath = entry.folderPath.hasSuffix("/") ? entry.folderPath : entry.folderPath + "/"
                return filePath.hasPrefix(folderPath) || filePath == entry.folderPath
            }
            .sorted { $0.folderPath.count > $1.folderPath.count }

        for entry in coveringEntries {
            guard let bookmarkData = entry.bookmarkData else { continue }

            var resolutionFailed = false
            let resolvedURL = bookmarkRefreshing.resolveURL(
                bookmarkData: bookmarkData,
                fallbackURL: entry.folderURL,
                onStale: { [weak self] _, refreshedBookmarkData in
                    self?.updateBookmarkData(forPath: entry.folderPath, bookmarkData: refreshedBookmarkData)
                },
                onFailure: { [weak self] in
                    resolutionFailed = true
                    self?.updateBookmarkData(forPath: entry.folderPath, bookmarkData: nil)
                }
            )

            if resolutionFailed { continue }
            return resolvedURL
        }

        return nil
    }

    func clearLinkAccessGrants() {
        mutate(coalescePersistence: false) { entries in
            entries = []
        }
    }

    private func updateBookmarkData(forPath folderPath: String, bookmarkData: Data?) {
        mutate(coalescePersistence: false) { entries in
            guard let index = entries.firstIndex(where: { $0.folderPath == folderPath }) else { return }
            let existing = entries[index]
            guard existing.bookmarkData != bookmarkData else { return }
            entries[index] = LinkAccessGrant(
                folderPath: existing.folderPath,
                bookmarkData: bookmarkData
            )
        }
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout [LinkAccessGrant]) -> Void
    ) {
        var updated = currentGrants
        transform(&updated)
        guard updated != currentGrants else { return }
        currentGrants = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
