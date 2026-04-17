import Foundation

enum ReaderDocumentLoadState: Equatable, Sendable {
    case ready
    case loading
    case deferred
    case settlingAutoOpen
}

enum ReaderStatusBarTimestamp: Equatable, Sendable {
    case updated(Date)
    case lastModified(Date)
}

struct PendingAutoOpenSettlingContext {
    let loadedMarkdown: String
    let diffBaselineMarkdown: String?
    let expiresAt: Date?
    let showsLoadingOverlay: Bool
}

enum PendingAutoOpenSettlingEvaluation {
    case unhandled
    case handled
}
