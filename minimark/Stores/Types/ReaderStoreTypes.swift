import Foundation

enum ReaderDocumentViewMode: String, CaseIterable, Sendable {
    case preview
    case split
    case source

    var displayName: String {
        switch self {
        case .preview:
            return "Preview"
        case .split:
            return "Split"
        case .source:
            return "Source"
        }
    }

    var next: ReaderDocumentViewMode {
        switch self {
        case .preview:
            return .split
        case .split:
            return .source
        case .source:
            return .preview
        }
    }
}

enum ReaderDocumentLoadState: Equatable, Sendable {
    case ready
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
