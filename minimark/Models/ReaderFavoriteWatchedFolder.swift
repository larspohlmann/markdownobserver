import Foundation

nonisolated struct ReaderFavoriteWatchedFolder: Equatable, Hashable, Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    let folderPath: String
    let options: FolderWatchOptions
    let bookmarkData: Data?
    let openDocumentRelativePaths: [String]
    let allKnownRelativePaths: [String]
    let createdAt: Date
    var workspaceState: ReaderFavoriteWorkspaceState

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
        case allKnownRelativePaths
        case createdAt
        case workspaceState
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderURL: URL,
        options: FolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
        allKnownRelativePaths: [String] = [],
        workspaceState: ReaderFavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        ),
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
        let computedOpenPaths = Self.scopedOpenDocumentRelativePaths(
            from: openDocumentFileURLs,
            relativeTo: normalizedURL,
            options: options
        )
        self.openDocumentRelativePaths = computedOpenPaths
        self.allKnownRelativePaths = allKnownRelativePaths.isEmpty
            ? computedOpenPaths
            : allKnownRelativePaths
        self.workspaceState = workspaceState
        self.createdAt = createdAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        options: FolderWatchOptions,
        bookmarkData: Data?,
        openDocumentRelativePaths: [String] = [],
        allKnownRelativePaths: [String] = [],
        workspaceState: ReaderFavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        ),
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
        self.allKnownRelativePaths = allKnownRelativePaths
        self.workspaceState = workspaceState
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        folderPath = try container.decode(String.self, forKey: .folderPath)
        options = try container.decode(FolderWatchOptions.self, forKey: .options)
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

        allKnownRelativePaths = try container.decodeIfPresent([String].self, forKey: .allKnownRelativePaths) ?? []

        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now

        workspaceState = try container.decodeIfPresent(
            ReaderFavoriteWorkspaceState.self,
            forKey: .workspaceState
        ) ?? .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(folderPath, forKey: .folderPath)
        try container.encode(options, forKey: .options)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(openDocumentRelativePaths, forKey: .openDocumentRelativePaths)
        try container.encode(allKnownRelativePaths, forKey: .allKnownRelativePaths)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(workspaceState, forKey: .workspaceState)
    }

    func newFileURLs(fromScanned scannedURLs: [URL], relativeTo folderURL: URL) -> [URL] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let folderPath = normalizedFolderURL.path
        let folderPathWithSlash = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        let knownSet = Set(allKnownRelativePaths)

        return scannedURLs.filter { url in
            let normalizedURL = ReaderFileRouting.normalizedFileURL(url)
            let filePath = normalizedURL.path
            guard filePath.hasPrefix(folderPathWithSlash) else { return false }
            let relativePath = String(filePath.dropFirst(folderPathWithSlash.count))
            return !relativePath.isEmpty && !knownSet.contains(relativePath)
        }
    }

    func resolvedOpenDocumentFileURLs(
        relativeTo folderURL: URL,
        options overrideOptions: FolderWatchOptions? = nil
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

    func existingOpenDocumentFileURLs(relativeTo folderURL: URL) -> [URL] {
        resolvedOpenDocumentFileURLs(relativeTo: folderURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func scopedOpenDocumentRelativePaths(
        from fileURLs: [URL],
        relativeTo folderURL: URL,
        options: FolderWatchOptions
    ) -> [String] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let folderPath = normalizedFolderURL.path
        let folderPathWithSlash = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        let excludedPaths = excludedPathSet(
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
                excludedPathSet: excludedPaths
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
        options: FolderWatchOptions
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
        options: FolderWatchOptions,
        folderPath: String,
        folderPathWithSlash: String,
        excludedPathSet: Set<String>
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

            return !FolderWatchExclusionCalculator.isPathExcludedBySelfOrAncestor(
                filePath,
                excludedSet: excludedPathSet
            )
        }
    }

    private static func excludedPathSet(
        relativeTo folderURL: URL,
        options: FolderWatchOptions,
        folderPathWithSlash: String
    ) -> Set<String> {
        guard options.scope == .includeSubfolders else {
            return []
        }

        let paths = options.resolvedExcludedSubdirectoryURLs(relativeTo: folderURL)
            .map(ReaderFileRouting.normalizedFileURL)
            .map(\.path)
            .filter { $0.hasPrefix(folderPathWithSlash) }
            .map(FolderWatchExclusionCalculator.normalizedDirectoryPath)

        return Set(paths)
    }

    nonisolated var excludedSubdirectoryRelativePaths: [String] {
        guard options.scope == .includeSubfolders else {
            return []
        }

        let folderPathValue = folderURL.path
        let folderPathWithSlash = folderPathValue.hasSuffix("/") ? folderPathValue : folderPathValue + "/"
        return options.excludedSubdirectoryPaths.compactMap { absolutePath in
            guard absolutePath.hasPrefix(folderPathWithSlash) else {
                return nil
            }
            return String(absolutePath.dropFirst(folderPathWithSlash.count))
        }.sorted()
    }

    func matches(folderPath: String, options: FolderWatchOptions) -> Bool {
        self.folderPath == folderPath && self.options == options
    }
}

nonisolated enum ReaderFavoriteHistory {
    static func insertingUniqueFavorite(
        name: String,
        folderURL: URL,
        options: FolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
        workspaceState: ReaderFavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        ),
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
            openDocumentFileURLs: openDocumentFileURLs,
            workspaceState: workspaceState
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
                allKnownRelativePaths: entry.allKnownRelativePaths,
                workspaceState: entry.workspaceState,
                createdAt: entry.createdAt
            )
        }
    }

    static func reordering(
        ids orderedIDs: [UUID],
        in existingEntries: [ReaderFavoriteWatchedFolder]
    ) -> [ReaderFavoriteWatchedFolder] {
        let lookup = Dictionary(existingEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = orderedIDs.compactMap { lookup[$0] }
        let resultIDs = Set(result.map(\.id))
        for entry in existingEntries where !resultIDs.contains(entry.id) {
            result.append(entry)
        }
        return result
    }
}
