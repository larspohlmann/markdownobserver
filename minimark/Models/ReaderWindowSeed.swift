import Foundation

enum ReaderOpenOrigin: String, Hashable, Codable, Sendable {
    case manual
    case folderWatchAutoOpen
    case folderWatchInitialBatchAutoOpen

    var isFolderWatchAutoOpen: Bool {
        switch self {
        case .manual:
            return false
        case .folderWatchAutoOpen, .folderWatchInitialBatchAutoOpen:
            return true
        }
    }

    var shouldNotifyFileAutoLoaded: Bool {
        self == .folderWatchAutoOpen
    }
}

struct ReaderWindowSeed: Hashable, Codable, Sendable {
    let id: UUID
    let filePath: String?
    let folderWatchSession: FolderWatchSession?
    let recentOpenedFile: ReaderRecentOpenedFile?
    let recentWatchedFolder: ReaderRecentWatchedFolder?
    let openOrigin: ReaderOpenOrigin
    let initialDiffBaselineMarkdown: String?

    init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        folderWatchSession: FolderWatchSession? = nil,
        recentOpenedFile: ReaderRecentOpenedFile? = nil,
        recentWatchedFolder: ReaderRecentWatchedFolder? = nil,
        openOrigin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        self.id = id
        self.filePath = fileURL?.path
        self.folderWatchSession = folderWatchSession
        self.recentOpenedFile = recentOpenedFile
        self.recentWatchedFolder = recentWatchedFolder
        self.openOrigin = openOrigin
        self.initialDiffBaselineMarkdown = initialDiffBaselineMarkdown
    }

    init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        folderWatchSession: FolderWatchSession? = nil,
        openOrigin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        self.init(
            id: id,
            fileURL: fileURL,
            folderWatchSession: folderWatchSession,
            recentOpenedFile: nil,
            recentWatchedFolder: nil,
            openOrigin: openOrigin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case folderWatchSession
        case recentOpenedFile
        case recentWatchedFolder
        case openOrigin
        case initialDiffBaselineMarkdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        folderWatchSession = try container.decodeIfPresent(FolderWatchSession.self, forKey: .folderWatchSession)
        recentOpenedFile = try container.decodeIfPresent(ReaderRecentOpenedFile.self, forKey: .recentOpenedFile)
        recentWatchedFolder = try container.decodeIfPresent(ReaderRecentWatchedFolder.self, forKey: .recentWatchedFolder)
        openOrigin = try container.decodeIfPresent(ReaderOpenOrigin.self, forKey: .openOrigin) ?? .manual
        initialDiffBaselineMarkdown = try container.decodeIfPresent(String.self, forKey: .initialDiffBaselineMarkdown)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(folderWatchSession, forKey: .folderWatchSession)
        try container.encodeIfPresent(recentOpenedFile, forKey: .recentOpenedFile)
        try container.encodeIfPresent(recentWatchedFolder, forKey: .recentWatchedFolder)
        try container.encode(openOrigin, forKey: .openOrigin)
        try container.encodeIfPresent(initialDiffBaselineMarkdown, forKey: .initialDiffBaselineMarkdown)
    }

    var fileURL: URL? {
        guard let filePath else {
            return nil
        }
        return URL(fileURLWithPath: filePath)
    }
}
