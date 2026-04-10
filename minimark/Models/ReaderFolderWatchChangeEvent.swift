import Foundation

enum ReaderFolderWatchChangeKind: String, Equatable, Hashable, Codable, Sendable {
    case added
    case modified
    case deleted
}

struct ReaderFolderWatchChangeEvent: Equatable, Hashable, Codable, Sendable {
    let fileURL: URL
    let kind: ReaderFolderWatchChangeKind
    let previousMarkdown: String?

    init(fileURL: URL, kind: ReaderFolderWatchChangeKind, previousMarkdown: String? = nil) {
        self.fileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        self.kind = kind
        self.previousMarkdown = previousMarkdown
    }
}
