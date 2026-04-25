import Foundation
import OSLog

@MainActor
final class SecurityScopeResolver {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "SecurityScopeResolver"
    )

    var context = SecurityScopeContext()

    private let securityScope: SecurityScopedResourceAccessing
    private let settingsStore: RecentWriting & TrustedFolderWriting & LinkAccessGrantWriting
    private let requestWatchedFolderReauthorization: (URL) -> URL?

    init(
        securityScope: SecurityScopedResourceAccessing,
        settingsStore: RecentWriting & TrustedFolderWriting & LinkAccessGrantWriting,
        requestWatchedFolderReauthorization: @escaping (URL) -> URL?
    ) {
        self.securityScope = securityScope
        self.settingsStore = settingsStore
        self.requestWatchedFolderReauthorization = requestWatchedFolderReauthorization
    }

    // MARK: - File Scope

    func activateFileSecurityScope(for url: URL, reason: String) {
        context.fileToken?.endAccess()
        context.fileToken = securityScope.beginAccess(to: url)
        if context.fileToken?.didStartAccess == true {
            context.accessibleFileURL = url
            context.accessibleFileURLSource = .fileScope
        }
    }

    func effectiveAccessibleFileURL(
        for url: URL,
        reason: String,
        folderWatchSession: FolderWatchSession?
    ) -> URL {
        let normalizedURL = FileRouting.normalizedFileURL(url)
        ensureFolderWatchAccessIfNeeded(for: normalizedURL, reason: reason, folderWatchSession: folderWatchSession)

        if let fileToken = context.fileToken,
           fileToken.didStartAccess,
           FileRouting.normalizedFileURL(fileToken.url) == normalizedURL {
            context.accessibleFileURL = fileToken.url
            context.accessibleFileURLSource = .fileScope
            return fileToken.url
        }

        if let accessibleFileURL = context.accessibleFileURL,
           context.accessibleFileURLSource == .fileScope,
           FileRouting.normalizedFileURL(accessibleFileURL) == normalizedURL {
            return accessibleFileURL
        }

        if let folderScopedFileURL = folderScopedAccessibleFileURL(
            for: normalizedURL,
            folderWatchSession: folderWatchSession
        ) {
            context.accessibleFileURL = folderScopedFileURL
            context.accessibleFileURLSource = .folderScopeChildURL
            return folderScopedFileURL
        }

        if let linkScopedFileURL = linkAccessScopedAccessibleFileURL(for: normalizedURL) {
            context.accessibleFileURL = linkScopedFileURL
            context.accessibleFileURLSource = .folderScopeChildURL
            return linkScopedFileURL
        }

        deriveFileSecurityScopeFromFolderIfNeeded(
            for: normalizedURL,
            reason: reason,
            folderWatchSession: folderWatchSession
        )

        if let fileToken = context.fileToken,
           fileToken.didStartAccess,
           FileRouting.normalizedFileURL(fileToken.url) == normalizedURL {
            context.accessibleFileURL = fileToken.url
            context.accessibleFileURLSource = .fileScope
            return fileToken.url
        }

        return normalizedURL
    }

    func endFileAndDirectoryAccess() {
        context.endFileAndDirectoryAccess()
    }

    // MARK: - Folder Scope

    func ensureFolderWatchAccessIfNeeded(
        for fileURL: URL,
        reason: String,
        folderWatchSession: FolderWatchSession?
    ) {
        guard let folderWatchSession,
              watchedFolderSession(folderWatchSession, appliesTo: fileURL) else {
            return
        }

        if context.folderToken?.didStartAccess == true {
            return
        }

        let accessURL = resolvedWatchedFolderAccessURL(for: folderWatchSession)
        context.folderToken?.endAccess()
        context.folderToken = securityScope.beginAccess(to: accessURL)
    }

    func folderScopedAccessibleFileURL(
        for fileURL: URL,
        folderWatchSession: FolderWatchSession?
    ) -> URL? {
        guard let folderWatchSession,
              watchedFolderSession(folderWatchSession, appliesTo: fileURL),
              let folderToken = context.folderToken,
              folderToken.didStartAccess else {
            return nil
        }

        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = FileRouting.normalizedFileURL(folderWatchSession.folderURL)
        let watchedFolderPath = normalizedWatchedFolderURL.path
        let filePath = normalizedFileURL.path

        guard filePath.hasPrefix(watchedFolderPath) else {
            return nil
        }

        let relativePath = filePath.dropFirst(watchedFolderPath.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            return folderToken.url
        }

        return URL(fileURLWithPath: relativePath, relativeTo: folderToken.url).standardizedFileURL
    }

    func resolvedWatchedFolderAccessURL(for session: FolderWatchSession) -> URL {
        settingsStore.resolvedRecentWatchedFolderURL(matching: session.folderURL) ?? session.folderURL
    }

    // MARK: - Link Access Grant Scope

    /// Activates folder-scoped access via a stored link-access grant covering
    /// `fileURL` and returns a folder-relative URL the loader can read.
    /// Returns nil if no grant covers the URL or the bookmark cannot be
    /// resolved.
    func linkAccessScopedAccessibleFileURL(for fileURL: URL) -> URL? {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        guard let grantFolderURL = settingsStore.resolvedLinkAccessFolderURL(containing: normalizedFileURL) else {
            return nil
        }

        if needsFolderTokenRefresh(for: grantFolderURL) {
            context.folderToken?.endAccess()
            context.folderToken = securityScope.beginAccess(to: grantFolderURL)
        }

        guard let folderToken = context.folderToken, folderToken.didStartAccess else {
            return nil
        }

        let folderPath = FileRouting.normalizedFileURL(folderToken.url).path
        let filePath = normalizedFileURL.path

        guard filePath.hasPrefix(folderPath) else { return nil }

        let relativePath = filePath.dropFirst(folderPath.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return folderToken.url }

        return URL(fileURLWithPath: relativePath, relativeTo: folderToken.url).standardizedFileURL
    }

    private func needsFolderTokenRefresh(for grantFolderURL: URL) -> Bool {
        guard let token = context.folderToken, token.didStartAccess else { return true }
        return FileRouting.normalizedFileURL(token.url) != FileRouting.normalizedFileURL(grantFolderURL)
    }

    // MARK: - Folder Session Helpers

    func watchedFolderSession(_ session: FolderWatchSession, appliesTo fileURL: URL) -> Bool {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = FileRouting.normalizedFileURL(session.folderURL)

        switch session.options.scope {
        case .selectedFolderOnly:
            return normalizedFileURL.deletingLastPathComponent().path == normalizedWatchedFolderURL.path
        case .includeSubfolders:
            let folderPath = normalizedWatchedFolderURL.path.hasSuffix("/")
                ? normalizedWatchedFolderURL.path
                : normalizedWatchedFolderURL.path + "/"
            return normalizedFileURL.path.hasPrefix(folderPath)
        }
    }

    func normalizedFolderWatchSession(_ session: FolderWatchSession) -> FolderWatchSession {
        FolderWatchSession(
            folderURL: FileRouting.normalizedFileURL(session.folderURL),
            options: session.options,
            startedAt: session.startedAt
        )
    }

    // MARK: - Write Recovery

    struct ReauthorizationResult {
        let succeeded: Bool
        let updatedSession: FolderWatchSession?
    }

    func tryReauthorizeWatchedFolder(
        after error: Error,
        for fileURL: URL,
        folderWatchSession: FolderWatchSession?
    ) -> ReauthorizationResult {
        guard isPermissionDeniedWriteError(error),
              let folderWatchSession,
              watchedFolderSession(folderWatchSession, appliesTo: fileURL) else {
            return ReauthorizationResult(succeeded: false, updatedSession: nil)
        }

        let watchedFolderURL = FileRouting.normalizedFileURL(folderWatchSession.folderURL)
        logInfo(
            "watched-folder reauthorization requested: file=\(redactedPathText(for: fileURL)) watchedFolder=\(redactedPathText(for: watchedFolderURL))"
        )

        guard let selectedFolderURL = requestWatchedFolderReauthorization(watchedFolderURL) else {
            logError(
                "watched-folder reauthorization cancelled: file=\(redactedPathText(for: fileURL))"
            )
            return ReauthorizationResult(succeeded: false, updatedSession: nil)
        }

        let normalizedSelectedFolderURL = FileRouting.normalizedFileURL(selectedFolderURL)
        guard normalizedSelectedFolderURL == watchedFolderURL else {
            logError(
                "watched-folder reauthorization mismatched selection: requested=\(redactedPathText(for: watchedFolderURL)) selected=\(redactedPathText(for: normalizedSelectedFolderURL))"
            )
            return ReauthorizationResult(succeeded: false, updatedSession: nil)
        }

        settingsStore.addRecentWatchedFolder(selectedFolderURL, options: folderWatchSession.options)
        context.folderToken?.endAccess()
        context.folderToken = securityScope.beginAccess(to: selectedFolderURL)

        let updatedSession = FolderWatchSession(
            folderURL: watchedFolderURL,
            options: folderWatchSession.options,
            startedAt: folderWatchSession.startedAt
        )

        context.fileToken?.endAccess()
        context.fileToken = nil
        context.accessibleFileURL = nil
        context.accessibleFileURLSource = nil

        logInfo(
            "watched-folder reauthorization completed: watchedFolder=\(redactedPathText(for: watchedFolderURL)) selected=\(redactedPathText(for: normalizedSelectedFolderURL)) started=\(context.folderToken?.didStartAccess == true)"
        )

        let succeeded = context.folderToken?.didStartAccess == true
        return ReauthorizationResult(succeeded: succeeded, updatedSession: succeeded ? updatedSession : nil)
    }

    func isPermissionDeniedWriteError(_ error: Error) -> Bool {
        let resolvedError: NSError
        if case let AppError.fileWriteFailed(_, underlying) = error {
            resolvedError = underlying as NSError
        } else {
            resolvedError = error as NSError
        }

        if resolvedError.domain == NSCocoaErrorDomain,
           resolvedError.code == NSFileWriteNoPermissionError {
            return true
        }

        if resolvedError.domain == NSPOSIXErrorDomain,
           [Int(EACCES), Int(EPERM)].contains(resolvedError.code) {
            return true
        }

        return false
    }

    // MARK: - Trusted Image Folder Access

    func activateTrustedImageFolderAccessIfNeeded(
        for directoryURL: URL?,
        folderWatchSession: FolderWatchSession?
    ) {
        guard let directoryURL else { return }

        if let folderWatchSession,
           watchedFolderSession(folderWatchSession, appliesTo: directoryURL.appendingPathComponent("dummy")),
           context.folderToken?.didStartAccess == true {
            return
        }

        if let directoryToken = context.directoryToken,
           directoryToken.didStartAccess,
           FileRouting.normalizedFileURL(directoryURL)
               .path.hasPrefix(FileRouting.normalizedFileURL(URL(fileURLWithPath: directoryToken.url.path)).path) {
            return
        }

        guard let resolvedURL = settingsStore.resolvedTrustedImageFolderURL(
            containing: directoryURL.appendingPathComponent("dummy")
        ) else {
            return
        }

        context.directoryToken?.endAccess()
        context.directoryToken = securityScope.beginAccess(to: resolvedURL)
        logInfo(
            "trusted image folder scope activated: directory=\(redactedPathText(for: directoryURL)) started=\(context.directoryToken?.didStartAccess == true)"
        )
    }

    func grantImageDirectoryAccess(folderURL: URL) {
        settingsStore.addTrustedImageFolder(folderURL)

        context.directoryToken?.endAccess()
        context.directoryToken = securityScope.beginAccess(to: folderURL)
        logInfo(
            "image directory access granted: folder=\(redactedPathText(for: folderURL)) started=\(context.directoryToken?.didStartAccess == true)"
        )
    }

    // MARK: - Derived File Scope

    private func deriveFileSecurityScopeFromFolderIfNeeded(
        for fileURL: URL,
        reason: String,
        folderWatchSession: FolderWatchSession?
    ) {
        guard let folderWatchSession,
              watchedFolderSession(folderWatchSession, appliesTo: fileURL),
              let folderToken = context.folderToken,
              folderToken.didStartAccess else {
            return
        }

        do {
            let folderScopedFileURL = folderScopedAccessibleFileURL(
                for: fileURL,
                folderWatchSession: folderWatchSession
            ) ?? fileURL
            let bookmarkData = try folderScopedFileURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var isStale = false
            let scopedFileURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                logInfo(
                    "bookmark stale while deriving file scope: reason=\(reason) file=\(redactedPathText(for: fileURL))"
                )
            }
            activateFileSecurityScope(for: scopedFileURL, reason: "\(reason)-derivedFromFolder")
        } catch {
            logInfo(
                "failed deriving file scope from folder: reason=\(reason) file=\(redactedPathText(for: fileURL)) error=\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Logging

    func redactedPathText(for url: URL?) -> String {
        guard let url else {
            return "none"
        }

        let normalizedURL = FileRouting.normalizedFileURL(url)
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
