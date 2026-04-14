import Foundation

nonisolated struct ReaderRecentOpenedFile: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 15

    let filePath: String
    let bookmarkData: Data?

    nonisolated var id: String {
        filePath
    }

    nonisolated var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    nonisolated var resolvedFileURL: URL {
        SecurityScopedBookmarkResolver.resolveSecurityScopedBookmark(bookmarkData, fallbackURL: fileURL)
    }

    nonisolated var displayName: String {
        let name = fileURL.lastPathComponent
        return name.isEmpty ? filePath : name
    }

    nonisolated var pathText: String {
        filePath
    }

    init(fileURL: URL) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
        filePath = normalizedURL.path
        bookmarkData = try? fileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(filePath: String, bookmarkData: Data?) {
        self.filePath = filePath
        self.bookmarkData = bookmarkData
    }
}
