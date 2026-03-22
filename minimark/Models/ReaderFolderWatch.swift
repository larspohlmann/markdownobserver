import Foundation

nonisolated enum ReaderFolderWatchAutoOpenPolicy {
    static let maximumInitialAutoOpenFileCount = 12
    static let maximumLiveAutoOpenFileCount = 12
}

nonisolated enum ReaderFolderWatchOpenMode: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
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

nonisolated enum ReaderFolderWatchScope: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
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

nonisolated struct ReaderFolderWatchOptions: Equatable, Hashable, Codable, Sendable {
    var openMode: ReaderFolderWatchOpenMode
    var scope: ReaderFolderWatchScope

    static let `default` = ReaderFolderWatchOptions(
        openMode: .watchChangesOnly,
        scope: .selectedFolderOnly
    )
}

nonisolated struct ReaderFolderWatchSession: Equatable, Hashable, Codable, Sendable {
    let folderURL: URL
    let options: ReaderFolderWatchOptions
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
        [
            (title: "When watch starts", value: options.openMode.label),
            (title: "Scope", value: options.scope.label)
        ]
    }

    nonisolated var tooltipText: String {
        [
            "Watching folder",
            detailPathText,
            "When watch starts: \(options.openMode.label)",
            "Scope: \(options.scope.label)"
        ].joined(separator: "\n")
    }

    nonisolated var accessibilityValue: String {
        folderDisplayName
    }
}

nonisolated struct ReaderFolderWatchAutoOpenWarning: Equatable, Identifiable, Sendable {
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
