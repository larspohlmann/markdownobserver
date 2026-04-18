import Foundation

enum FolderWatchChangeKind: String, Equatable, Hashable, Codable, Sendable {
    case added
    case modified
    case deleted
}

struct FolderWatchChangeEvent: Equatable, Hashable, Codable, Sendable {
    let fileURL: URL
    let kind: FolderWatchChangeKind
    let previousMarkdown: String?

    init(fileURL: URL, kind: FolderWatchChangeKind, previousMarkdown: String? = nil) {
        self.fileURL = FileRouting.normalizedFileURL(fileURL)
        self.kind = kind
        self.previousMarkdown = previousMarkdown
    }
}
