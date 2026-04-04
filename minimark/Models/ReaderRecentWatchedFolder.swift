import Foundation

nonisolated struct ReaderRecentWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 15

    let folderPath: String
    let options: ReaderFolderWatchOptions
    let bookmarkData: Data?

    nonisolated var id: String {
        folderPath
    }

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    nonisolated var displayName: String {
        let name = folderURL.lastPathComponent
        return name.isEmpty ? folderPath : name
    }

    nonisolated var pathText: String {
        folderPath
    }

    nonisolated var resolvedFolderURL: URL {
        guard let bookmarkData else {
            return folderURL
        }

        var bookmarkIsStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            return folderURL
        }

        return resolvedURL
    }

    init(folderURL: URL, options: ReaderFolderWatchOptions) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(folderURL)
        folderPath = normalizedURL.path
        self.options = options
        bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(folderPath: String, options: ReaderFolderWatchOptions, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.options = options
        self.bookmarkData = bookmarkData
    }
}
