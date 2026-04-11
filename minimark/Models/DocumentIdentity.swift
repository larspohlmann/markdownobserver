import Foundation

struct DocumentIdentity {
    var fileURL: URL?
    var fileDisplayName: String = ""
    var documentLoadState: ReaderDocumentLoadState = .ready
    var isCurrentFileMissing: Bool = false
    var lastError: ReaderPresentableError?
    var openInApplications: [ReaderExternalApplication] = []
    var needsImageDirectoryAccess: Bool = false
    var currentOpenOrigin: ReaderOpenOrigin = .manual

    static let empty = DocumentIdentity()

    var hasOpenDocument: Bool { fileURL != nil }
    var isDeferredDocument: Bool { documentLoadState == .deferred }
    var windowTitle: String {
        fileDisplayName.isEmpty ? "MarkdownObserver" : "\(fileDisplayName) - MarkdownObserver"
    }
}
