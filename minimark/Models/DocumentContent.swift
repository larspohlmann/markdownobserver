import Foundation

enum ReaderExternalChangeKind: Equatable, Sendable {
    case added
    case modified
}

struct DocumentContent {
    var savedMarkdown: String = ""
    var sourceMarkdown: String = ""
    var renderedHTMLDocument: String = ""
    var changedRegions: [ChangedRegion] = []
    var lastRefreshAt: Date?
    var fileLastModifiedAt: Date?
    var lastExternalChangeAt: Date?
    var hasUnacknowledgedExternalChange: Bool = false
    var unacknowledgedExternalChangeKind: ReaderExternalChangeKind = .modified

    static let empty = DocumentContent()
}
