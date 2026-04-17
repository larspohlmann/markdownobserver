import Foundation
import Combine
import Observation

@MainActor @Observable final class RecentOpenedFilesStore: RecentOpenedFileWriting {
    private(set) var currentRecentOpenedFiles: [RecentOpenedFile]

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<[RecentOpenedFile], Never>

    @ObservationIgnored
    private let bookmarkRefreshing: BookmarkRefreshing

    var recentOpenedFilesPublisher: AnyPublisher<[RecentOpenedFile], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: [RecentOpenedFile], bookmarkRefreshing: BookmarkRefreshing) {
        self.currentRecentOpenedFiles = initial
        self.subject = CurrentValueSubject(initial)
        self.bookmarkRefreshing = bookmarkRefreshing
    }

    func addRecentManuallyOpenedFile(_ fileURL: URL) {
        mutate(coalescePersistence: false) { entries in
            entries = RecentHistory.insertingUniqueFile(fileURL, into: entries)
        }
    }

    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        guard let entry = currentRecentOpenedFiles.first(where: { entry in
            FileRouting.normalizedFileURL(entry.fileURL) == normalizedFileURL
        }) else {
            return nil
        }

        return bookmarkRefreshing.resolveURL(
            bookmarkData: entry.bookmarkData,
            fallbackURL: entry.fileURL,
            onStale: { [weak self] _, refreshedBookmarkData in
                self?.updateBookmarkData(forPath: entry.filePath, bookmarkData: refreshedBookmarkData)
            },
            onFailure: { [weak self] in
                self?.updateBookmarkData(forPath: entry.filePath, bookmarkData: nil)
            }
        )
    }

    func clearRecentManuallyOpenedFiles() {
        mutate(coalescePersistence: false) { entries in
            entries = []
        }
    }

    private func updateBookmarkData(forPath filePath: String, bookmarkData: Data?) {
        mutate(coalescePersistence: false) { entries in
            guard let index = entries.firstIndex(where: { $0.filePath == filePath }) else { return }
            let existing = entries[index]
            guard existing.bookmarkData != bookmarkData else { return }
            entries[index] = RecentOpenedFile(
                filePath: existing.filePath,
                bookmarkData: bookmarkData
            )
        }
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout [RecentOpenedFile]) -> Void
    ) {
        var updated = currentRecentOpenedFiles
        transform(&updated)
        guard updated != currentRecentOpenedFiles else { return }
        currentRecentOpenedFiles = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
