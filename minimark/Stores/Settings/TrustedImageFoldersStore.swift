import Foundation
import Combine
import Observation

@MainActor @Observable final class TrustedImageFoldersStore: ReaderTrustedFolderWriting {
    private(set) var currentTrustedFolders: [TrustedImageFolder]

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<[TrustedImageFolder], Never>

    @ObservationIgnored
    private let bookmarkRefreshing: BookmarkRefreshing

    var trustedFoldersPublisher: AnyPublisher<[TrustedImageFolder], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: [TrustedImageFolder], bookmarkRefreshing: BookmarkRefreshing) {
        self.currentTrustedFolders = initial
        self.subject = CurrentValueSubject(initial)
        self.bookmarkRefreshing = bookmarkRefreshing
    }

    func addTrustedImageFolder(_ folderURL: URL) {
        mutate(coalescePersistence: false) { entries in
            entries = ReaderTrustedImageFolderHistory.insertingUnique(folderURL, into: entries)
        }
    }

    func resolvedTrustedImageFolderURL(containing fileURL: URL) -> URL? {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let filePath = normalizedFileURL.path

        for entry in currentTrustedFolders {
            let folderPath = entry.folderPath.hasSuffix("/") ? entry.folderPath : entry.folderPath + "/"
            guard filePath.hasPrefix(folderPath) else { continue }
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

            if resolutionFailed {
                continue
            }
            return resolvedURL
        }

        return nil
    }

    private func updateBookmarkData(forPath folderPath: String, bookmarkData: Data?) {
        mutate(coalescePersistence: false) { entries in
            guard let index = entries.firstIndex(where: { $0.folderPath == folderPath }) else { return }
            let existing = entries[index]
            guard existing.bookmarkData != bookmarkData else { return }
            entries[index] = TrustedImageFolder(
                folderPath: existing.folderPath,
                bookmarkData: bookmarkData
            )
        }
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout [TrustedImageFolder]) -> Void
    ) {
        var updated = currentTrustedFolders
        transform(&updated)
        guard updated != currentTrustedFolders else { return }
        currentTrustedFolders = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
