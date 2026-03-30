import Foundation

nonisolated struct ReaderFavoriteWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let folderPath: String
    let options: ReaderFolderWatchOptions
    let bookmarkData: Data?
    let openDocumentRelativePaths: [String]
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case folderPath
        case options
        case bookmarkData
        case openDocumentRelativePaths
        case createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
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
        self.openDocumentRelativePaths = Self.scopedOpenDocumentRelativePaths(
            from: openDocumentFileURLs,
            relativeTo: normalizedURL,
            options: options
        )
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        options: ReaderFolderWatchOptions,
        bookmarkData: Data?,
        openDocumentRelativePaths: [String] = [],
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.options = options
        self.bookmarkData = bookmarkData
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(
            URL(fileURLWithPath: folderPath, isDirectory: true)
        )
        self.openDocumentRelativePaths = Self.scopedOpenDocumentRelativePaths(
            fromRelativePaths: openDocumentRelativePaths,
            relativeTo: normalizedFolderURL,
            options: options
        )
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        folderPath = try container.decode(String.self, forKey: .folderPath)
        options = try container.decode(ReaderFolderWatchOptions.self, forKey: .options)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(
            URL(fileURLWithPath: folderPath, isDirectory: true)
        )
        let decodedRelativePaths = try container.decodeIfPresent(
            [String].self,
            forKey: .openDocumentRelativePaths
        ) ?? []
        openDocumentRelativePaths = Self.scopedOpenDocumentRelativePaths(
            fromRelativePaths: decodedRelativePaths,
            relativeTo: normalizedFolderURL,
            options: options
        )

        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(openDocumentRelativePaths, forKey: .openDocumentRelativePaths)
        try container.encode(createdAt, forKey: .createdAt)
    }

    func resolvedOpenDocumentFileURLs(
        relativeTo folderURL: URL,
        options overrideOptions: ReaderFolderWatchOptions? = nil
    ) -> [URL] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let effectiveOptions = overrideOptions ?? options
        let scopedRelativePaths = Self.scopedOpenDocumentRelativePaths(
            fromRelativePaths: openDocumentRelativePaths,
            relativeTo: normalizedFolderURL,
            options: effectiveOptions
        )

        return scopedRelativePaths.map {
            ReaderFileRouting.normalizedFileURL(
                normalizedFolderURL.appendingPathComponent($0, isDirectory: false)
            )
        }
    }

    static func scopedOpenDocumentRelativePaths(
        from fileURLs: [URL],
        relativeTo folderURL: URL,
        options: ReaderFolderWatchOptions
    ) -> [String] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let folderPath = normalizedFolderURL.path
        let folderPathWithSlash = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        let excludedDirectoryPaths = excludedDirectoryPaths(
            relativeTo: normalizedFolderURL,
            options: options,
            folderPathWithSlash: folderPathWithSlash
        )

        let scopedRelativePaths = fileURLs.compactMap { fileURL -> String? in
            let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
            guard fileURLIsInScope(
                normalizedFileURL,
                options: options,
                folderPath: folderPath,
                folderPathWithSlash: folderPathWithSlash,
                excludedDirectoryPaths: excludedDirectoryPaths
            ) else {
                return nil
            }

            let relativePath = String(normalizedFileURL.path.dropFirst(folderPathWithSlash.count))
            return relativePath.isEmpty ? nil : relativePath
        }

        return Array(Set(scopedRelativePaths)).sorted()
    }

    private static func scopedOpenDocumentRelativePaths(
        fromRelativePaths relativePaths: [String],
        relativeTo folderURL: URL,
        options: ReaderFolderWatchOptions
    ) -> [String] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let candidateURLs = relativePaths.compactMap { path -> URL? in
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty,
                  !trimmedPath.hasPrefix("/") else {
                return nil
            }

            return ReaderFileRouting.normalizedFileURL(
                normalizedFolderURL.appendingPathComponent(trimmedPath, isDirectory: false)
            )
        }

        return scopedOpenDocumentRelativePaths(
            from: candidateURLs,
            relativeTo: normalizedFolderURL,
            options: options
        )
    }

    private static func fileURLIsInScope(
        _ fileURL: URL,
        options: ReaderFolderWatchOptions,
        folderPath: String,
        folderPathWithSlash: String,
        excludedDirectoryPaths: [String]
    ) -> Bool {
        guard ReaderFileRouting.isSupportedMarkdownFileURL(fileURL) else {
            return false
        }

        let filePath = fileURL.path
        switch options.scope {
        case .selectedFolderOnly:
            return fileURL.deletingLastPathComponent().path == folderPath
        case .includeSubfolders:
            guard filePath.hasPrefix(folderPathWithSlash) else {
                return false
            }

            return !filePathIsExcluded(
                filePath,
                excludedDirectoryPaths: excludedDirectoryPaths
            )
        }
    }

    private static func filePathIsExcluded(
        _ filePath: String,
        excludedDirectoryPaths: [String]
    ) -> Bool {
        for excludedPath in excludedDirectoryPaths {
            if filePath == excludedPath {
                return true
            }

            let excludedPathWithSlash = excludedPath.hasSuffix("/")
                ? excludedPath
                : excludedPath + "/"
            if filePath.hasPrefix(excludedPathWithSlash) {
                return true
            }
        }

        return false
    }

    private static func excludedDirectoryPaths(
        relativeTo folderURL: URL,
        options: ReaderFolderWatchOptions,
        folderPathWithSlash: String
    ) -> [String] {
        guard options.scope == .includeSubfolders else {
            return []
        }

        return options.resolvedExcludedSubdirectoryURLs(relativeTo: folderURL)
            .map(ReaderFileRouting.normalizedFileURL)
            .map(\.path)
            .filter { $0.hasPrefix(folderPathWithSlash) }
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
        openDocumentFileURLs: [URL] = [],
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
            options: options,
            openDocumentFileURLs: openDocumentFileURLs
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
                openDocumentRelativePaths: entry.openDocumentRelativePaths,
                createdAt: entry.createdAt
            )
        }
    }
}
