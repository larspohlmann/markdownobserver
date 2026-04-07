import Foundation

enum ReaderExternalChangeKind: Equatable, Sendable {
    case added
    case modified
}

struct ReaderDocumentState {
    var fileURL: URL?
    var fileDisplayName: String = ""
    var savedMarkdown: String = ""
    var draftMarkdown: String?
    var pendingSavedDraftDiffBaselineMarkdown: String?
    var sourceMarkdown: String = ""
    var sourceEditorSeedMarkdown: String = ""
    var renderedHTMLDocument: String = ""
    var documentViewMode: ReaderDocumentViewMode = .preview
    var documentLoadState: ReaderDocumentLoadState = .ready
    var changedRegions: [ChangedRegion] = []
    var unsavedChangedRegions: [ChangedRegion] = []
    var lastRefreshAt: Date?
    var lastExternalChangeAt: Date?
    var fileLastModifiedAt: Date?
    var hasUnacknowledgedExternalChange: Bool = false
    var unacknowledgedExternalChangeKind: ReaderExternalChangeKind = .modified
    var openInApplications: [ReaderExternalApplication] = []
    var lastError: ReaderPresentableError?
    var isCurrentFileMissing: Bool = false
    var isSourceEditing: Bool = false
    var hasUnsavedDraftChanges: Bool = false
    var needsImageDirectoryAccess: Bool = false
    var currentOpenOrigin: ReaderOpenOrigin = .manual

    static let empty = ReaderDocumentState()

    var windowTitle: String {
        fileDisplayName.isEmpty ? "MarkdownObserver" : "\(fileDisplayName) - MarkdownObserver"
    }

    var decoratedWindowTitle: String {
        (hasUnacknowledgedExternalChange || hasUnsavedDraftChanges) ? "* \(windowTitle)" : windowTitle
    }

    var hasOpenDocument: Bool {
        fileURL != nil
    }

    var isDeferredDocument: Bool {
        documentLoadState == .deferred
    }

    var canStartSourceEditing: Bool {
        hasOpenDocument && !isCurrentFileMissing && !isSourceEditing
    }

    var canSaveSourceDraft: Bool {
        isSourceEditing && hasUnsavedDraftChanges
    }

    var canDiscardSourceDraft: Bool {
        isSourceEditing
    }

    var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let lastExternalChangeAt {
            return .updated(lastExternalChangeAt)
        }
        if let fileLastModifiedAt {
            return .lastModified(fileLastModifiedAt)
        }
        if let lastRefreshAt {
            return .updated(lastRefreshAt)
        }
        return nil
    }
}
