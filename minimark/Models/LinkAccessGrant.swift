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

    init(folderPath: String, bookmarkData: Data?) {
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
    }
}

nonisolated enum LinkAccessGrantHistory {
    /// Returns `existingEntries` unchanged when `bookmarkData` is `nil` —
    /// persisting a grant without a usable bookmark would re-prompt forever:
    /// the resolver would skip the bookmark-less entry and the coordinator
    /// would see no covering grant on the next click.
    static func insertingUnique(
        _ folderURL: URL,
        bookmarkData: Data?,
        into existingEntries: [LinkAccessGrant]
    ) -> [LinkAccessGrant] {
        guard let bookmarkData else { return existingEntries }
        let normalizedURL = FileRouting.normalizedFileURL(folderURL)
        let newEntry = LinkAccessGrant(folderPath: normalizedURL.path, bookmarkData: bookmarkData)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(LinkAccessGrant.maximumCount))
    }
}
