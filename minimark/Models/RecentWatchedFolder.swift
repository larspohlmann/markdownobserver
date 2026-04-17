import Foundation

nonisolated struct RecentWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 15

    let folderPath: String
    let options: FolderWatchOptions
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
        SecurityScopedBookmarkResolver.resolveSecurityScopedBookmark(bookmarkData, fallbackURL: folderURL)
    }

    init(folderURL: URL, options: FolderWatchOptions) {
        let normalizedURL = FileRouting.normalizedFileURL(folderURL)
        folderPath = normalizedURL.path
        self.options = options
        bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(folderPath: String, options: FolderWatchOptions, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.options = options
        self.bookmarkData = bookmarkData
    }
}
