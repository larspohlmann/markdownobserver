import Foundation
import OSLog

@MainActor
struct SaveLogFormatter {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "SaveLogFormatter"
    )

    let securityScopeResolver: SecurityScopeResolver
    let document: ReaderDocumentController
    let sourceEditingController: ReaderSourceEditingController
    let folderWatchDispatcher: FolderWatchDispatcher

    func saveContext(for url: URL?) -> String {
        let filePath = redactedPath(for: url)
        let watchedFolderPath = redactedPath(for: folderWatchDispatcher.activeFolderWatchSession?.folderURL)
        let ctx = securityScopeResolver.context
        let fileScopeURL = redactedPath(for: ctx.fileToken?.url)
        let folderScopeURL = redactedPath(for: ctx.folderToken?.url)
        let accessibleFilePath = redactedPath(for: ctx.accessibleFileURL)
        return "file=\(filePath) origin=\(document.currentOpenOrigin.rawValue) editing=\(sourceEditingController.isSourceEditing) unsaved=\(sourceEditingController.hasUnsavedDraftChanges) fileScope=\(ctx.fileToken != nil) fileScopeStarted=\(ctx.fileToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(ctx.folderToken != nil) folderScopeStarted=\(ctx.folderToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
    }

    func redactedPath(for url: URL?) -> String {
        guard let url else {
            return "none"
        }
        let normalizedURL = ReaderFileRouting.normalizedFileURL(url)
        let name = normalizedURL.lastPathComponent.isEmpty ? "root" : normalizedURL.lastPathComponent
        let pathHash = String(normalizedURL.path.hashValue.magnitude, radix: 16)
        return "\(name)#\(pathHash)"
    }

    func logInfo(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
    }

    func logError(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
    }
}
