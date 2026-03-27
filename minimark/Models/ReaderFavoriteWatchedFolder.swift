import Foundation

nonisolated struct ReaderFavoriteWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let folderPath: String
    let options: ReaderFolderWatchOptions
    let bookmarkData: Data?
    let createdAt: Date

    nonisolated var folderURL: URL {
        URL(fileURLWithPath: folderPath)
    }

    nonisolated var displayName: String {
        let folderName = folderURL.lastPathComponent
        return folderName.isEmpty ? folderPath : folderName
    }

    nonisolated var pathText: String {
        folderPath
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        let normalizedURL = ReaderFileRouting.normalizedFileURL(folderURL)
        self.folderPath = normalizedURL.path
        self.options = options
        self.bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        options: ReaderFolderWatchOptions,
        bookmarkData: Data?,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.options = options
        self.bookmarkData = bookmarkData
        self.createdAt = createdAt
    }

    func matches(folderPath: String, options: ReaderFolderWatchOptions) -> Bool {
        self.folderPath == folderPath && self.options == options
    }
}

nonisolated enum ReaderFavoriteHistory {
    static func insertingUniqueFavorite(
        name: String,
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        into existingEntries: [ReaderFavoriteWatchedFolder]
    ) -> [ReaderFavoriteWatchedFolder] {
        let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path

        let alreadyExists = existingEntries.contains {
            $0.matches(folderPath: normalizedPath, options: options)
        }
        guard !alreadyExists else {
            return existingEntries
        }

        let newEntry = ReaderFavoriteWatchedFolder(
            name: name,
            folderURL: folderURL,
            options: options
        )
        return existingEntries + [newEntry]
    }

    static func removingFavorite(
        id: UUID,
        from existingEntries: [ReaderFavoriteWatchedFolder]
    ) -> [ReaderFavoriteWatchedFolder] {
        existingEntries.filter { $0.id != id }
    }

    static func renamingFavorite(
        id: UUID,
        newName: String,
        in existingEntries: [ReaderFavoriteWatchedFolder]
    ) -> [ReaderFavoriteWatchedFolder] {
        existingEntries.map { entry in
            guard entry.id == id else { return entry }
            return ReaderFavoriteWatchedFolder(
                id: entry.id,
                name: newName,
                folderPath: entry.folderPath,
                options: entry.options,
                bookmarkData: entry.bookmarkData,
                createdAt: entry.createdAt
            )
        }
    }
}
