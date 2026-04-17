import Foundation

@MainActor
final class MarkdownFileLoader {
    private let securityScopeResolver: SecurityScopeResolver
    private let fileIO: DocumentIO

    init(securityScopeResolver: SecurityScopeResolver, fileIO: DocumentIO) {
        self.securityScopeResolver = securityScopeResolver
        self.fileIO = fileIO
    }

    func load(
        at url: URL,
        folderWatchSession: FolderWatchSession?
    ) throws -> (markdown: String, modificationDate: Date) {
        let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
            for: url, reason: "read", folderWatchSession: folderWatchSession
        )
        return try fileIO.load(at: accessibleURL)
    }
}
