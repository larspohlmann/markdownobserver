import Foundation
import Combine
import Observation

@MainActor @Observable final class RecentWatchedFoldersStore: RecentWatchedFolderWriting {
    private(set) var currentRecentWatchedFolders: [RecentWatchedFolder]

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<[RecentWatchedFolder], Never>

    @ObservationIgnored
    private let bookmarkRefreshing: BookmarkRefreshing

    var recentWatchedFoldersPublisher: AnyPublisher<[RecentWatchedFolder], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: [RecentWatchedFolder], bookmarkRefreshing: BookmarkRefreshing) {
        self.currentRecentWatchedFolders = initial
        self.subject = CurrentValueSubject(initial)
        self.bookmarkRefreshing = bookmarkRefreshing
    }

    func addRecentWatchedFolder(_ folderURL: URL, options: FolderWatchOptions) {
        mutate(coalescePersistence: false) { entries in
            entries = RecentHistory.insertingUniqueWatchedFolder(
                folderURL,
                options: options,
                into: entries
            )
        }
    }

    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
        guard let entry = currentRecentWatchedFolders.first(where: { entry in
            FileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
        }) else {
            return nil
        }

        return bookmarkRefreshing.resolveURL(
            bookmarkData: entry.bookmarkData,
            fallbackURL: entry.folderURL,
            onStale: { [weak self] _, refreshedBookmarkData in
                self?.updateBookmarkData(forPath: entry.folderPath, bookmarkData: refreshedBookmarkData)
            },
            onFailure: { [weak self] in
                self?.updateBookmarkData(forPath: entry.folderPath, bookmarkData: nil)
            }
        )
    }

    func clearRecentWatchedFolders() {
        mutate(coalescePersistence: false) { entries in
            entries = []
        }
    }

    private func updateBookmarkData(forPath folderPath: String, bookmarkData: Data?) {
        mutate(coalescePersistence: false) { entries in
            guard let index = entries.firstIndex(where: { $0.folderPath == folderPath }) else { return }
            let existing = entries[index]
            guard existing.bookmarkData != bookmarkData else { return }
            entries[index] = RecentWatchedFolder(
                folderPath: existing.folderPath,
                options: existing.options,
                bookmarkData: bookmarkData
            )
        }
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout [RecentWatchedFolder]) -> Void
    ) {
        var updated = currentRecentWatchedFolders
        transform(&updated)
        guard updated != currentRecentWatchedFolders else { return }
        currentRecentWatchedFolders = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
