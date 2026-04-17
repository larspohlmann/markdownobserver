import Foundation

enum DocumentLoadState: Equatable, Sendable {
    case ready
    case loading
    case deferred
    case settlingAutoOpen
}

enum StatusBarTimestamp: Equatable, Sendable {
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
