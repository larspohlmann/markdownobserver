import Foundation

/// User-granted folder access bookmark used to read markdown files reached via
/// link clicks inside the rendered preview. The sandbox grants per-file access
/// when the user opens a document; siblings and descendants in the same folder
/// require an explicit folder-scoped bookmark, which we collect on demand the
/// first time a link points outside the currently-accessible scope.
nonisolated struct LinkAccessGrant: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 50

    let folderPath: String
    let bookmarkData: Data?

    nonisolated var id: String {
        folderPath
    }

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    init(folderURL: URL) {
        let normalizedURL = FileRouting.normalizedFileURL(folderURL)
        folderPath = normalizedURL.path
        bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(folderPath: String, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
    }
}

nonisolated enum LinkAccessGrantHistory {
    static func insertingUnique(
        _ folderURL: URL,
        into existingEntries: [LinkAccessGrant]
    ) -> [LinkAccessGrant] {
        let newEntry = LinkAccessGrant(folderURL: folderURL)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(LinkAccessGrant.maximumCount))
    }
}
