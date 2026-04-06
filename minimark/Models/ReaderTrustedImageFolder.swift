import Foundation

nonisolated struct ReaderTrustedImageFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    static let maximumCount = 30

    let folderPath: String
    let bookmarkData: Data?

    nonisolated var id: String {
        folderPath
    }

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    init(folderURL: URL) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(folderURL)
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

nonisolated enum ReaderTrustedImageFolderHistory {
    static func insertingUnique(
        _ folderURL: URL,
        into existingEntries: [ReaderTrustedImageFolder]
    ) -> [ReaderTrustedImageFolder] {
        let newEntry = ReaderTrustedImageFolder(folderURL: folderURL)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(ReaderTrustedImageFolder.maximumCount))
    }
}
