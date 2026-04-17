import Foundation

nonisolated enum FolderWatchAutoOpenPolicy {
    static let maximumInitialAutoOpenFileCount = 12
    static let maximumLiveAutoOpenFileCount = 12
    static let performanceWarningFileCount = 50
}

nonisolated enum FolderWatchPerformancePolicy {
    static let exclusionPromptSubdirectoryThreshold = 256
    static let maximumSupportedSubdirectoryCount = 9_000
    static let maximumIncludedSubfolderDepth = 5
    static let recursiveEventSourceSafetyPollingIntervalSeconds = 5
}

nonisolated enum FolderWatchOpenMode: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case openAllMarkdownFiles
    case watchChangesOnly

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .openAllMarkdownFiles:
            return "Open all Markdown files"
        case .watchChangesOnly:
            return "Only watch for changes"
        }
    }
}

nonisolated enum FolderWatchScope: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case selectedFolderOnly
    case includeSubfolders

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .selectedFolderOnly:
            return "Selected folder only"
        case .includeSubfolders:
            return "Include subfolders"
        }
    }
}

nonisolated struct FolderWatchOptions: Equatable, Hashable, Codable, Sendable {
    var openMode: FolderWatchOpenMode
    var scope: FolderWatchScope
    var excludedSubdirectoryPaths: [String]

    static let `default` = FolderWatchOptions(
        openMode: .watchChangesOnly,
        scope: .selectedFolderOnly,
        excludedSubdirectoryPaths: []
    )

    init(
        openMode: FolderWatchOpenMode,
        scope: FolderWatchScope,
        excludedSubdirectoryPaths: [String] = []
    ) {
        self.openMode = openMode
        self.scope = scope
        self.excludedSubdirectoryPaths = excludedSubdirectoryPaths
    }

    private enum CodingKeys: String, CodingKey {
        case openMode
        case scope
        case excludedSubdirectoryPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        openMode = try container.decode(FolderWatchOpenMode.self, forKey: .openMode)
        scope = try container.decode(FolderWatchScope.self, forKey: .scope)
        excludedSubdirectoryPaths = try container.decodeIfPresent([String].self, forKey: .excludedSubdirectoryPaths) ?? []
    }

    func encodedForFolder(_ folderURL: URL) -> FolderWatchOptions {
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
        let normalizedExclusions = Self.normalizedExcludedSubdirectoryPaths(
            excludedSubdirectoryPaths,
            relativeTo: normalizedFolderURL
        )

        return FolderWatchOptions(
            openMode: openMode,
            scope: scope,
            excludedSubdirectoryPaths: normalizedExclusions
        )
    }

    func resolvedExcludedSubdirectoryURLs(relativeTo folderURL: URL) -> [URL] {
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
        return Self.normalizedExcludedSubdirectoryPaths(
            excludedSubdirectoryPaths,
            relativeTo: normalizedFolderURL
        ).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    private static func normalizedExcludedSubdirectoryPaths(
        _ paths: [String],
        relativeTo folderURL: URL
    ) -> [String] {
        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)

        let normalized = paths.compactMap { path -> String? in
            guard !path.isEmpty else {
                return nil
            }

            let candidateURL = FileRouting.normalizedFileURL(URL(fileURLWithPath: path, isDirectory: true))
            guard candidateURL.path != normalizedFolderURL.path else {
                return nil
            }

            let folderPath = normalizedFolderURL.path.hasSuffix("/") ? normalizedFolderURL.path : normalizedFolderURL.path + "/"
            guard candidateURL.path.hasPrefix(folderPath) else {
                return nil
            }

            return candidateURL.path
        }

        return Array(Set(normalized)).sorted()
    }
}

nonisolated struct FolderWatchSession: Equatable, Hashable, Codable, Sendable {
    let folderURL: URL
    let options: FolderWatchOptions
    let startedAt: Date

    private nonisolated var folderDisplayName: String {
        let lastPathComponent = folderURL.lastPathComponent
        return lastPathComponent.isEmpty ? folderURL.path : lastPathComponent
    }

    nonisolated var chipLabel: String {
        "Watching folder: \(folderDisplayName)"
    }

    nonisolated var statusLabel: String {
        "Watching \(folderDisplayName)"
    }

    nonisolated var titleLabel: String {
        chipLabel
    }

    nonisolated var detailSummaryTitle: String {
        folderDisplayName
    }

    nonisolated var detailPathText: String {
        folderURL.path
    }

    nonisolated var detailRows: [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = [
            (title: "When watch starts", value: options.openMode.label),
            (title: "Scope", value: options.scope.label)
        ]

        if options.scope == .includeSubfolders {
            rows.append((
                title: "Filtered subdirectories",
                value: String(options.excludedSubdirectoryPaths.count)
            ))
        }

        return rows
    }

    nonisolated var excludedSubdirectoryRelativePaths: [String] {
        guard options.scope == .includeSubfolders else {
            return []
        }

        let folderPath = folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/"
        return options.excludedSubdirectoryPaths.compactMap { absolutePath in
            guard absolutePath.hasPrefix(folderPath) else {
                return nil
            }
            return String(absolutePath.dropFirst(folderPath.count))
        }.sorted()
    }

    nonisolated var tooltipText: String {
        var lines = [
            "Watching folder",
            detailPathText,
            "When watch starts: \(options.openMode.label)",
            "Scope: \(options.scope.label)"
        ]

        if options.scope == .includeSubfolders {
            lines.append("Filtered subdirectories: \(options.excludedSubdirectoryPaths.count)")
        }

        return lines.joined(separator: "\n")
    }

    nonisolated var accessibilityValue: String {
        folderDisplayName
    }
}

nonisolated struct FolderWatchAutoOpenWarning: Equatable, Identifiable, Sendable {
    let folderURL: URL
    let autoOpenedFileCount: Int
    let omittedFileURLs: [URL]

    nonisolated var id: String {
        "\(folderURL.path)|\(autoOpenedFileCount)|\(omittedFileURLs.count)"
    }

    nonisolated var remainingFileCount: Int {
        omittedFileURLs.count
    }

    nonisolated var totalFileCount: Int {
        autoOpenedFileCount + remainingFileCount
    }
}

@MainActor
final class FolderWatchFileSelectionRequest: Identifiable {
    let id = UUID()
    let folderURL: URL
    let session: FolderWatchSession
    let allFileURLs: [URL]

    init(folderURL: URL, session: FolderWatchSession, allFileURLs: [URL]) {
        self.folderURL = folderURL
        self.session = session
        self.allFileURLs = allFileURLs
    }
}
