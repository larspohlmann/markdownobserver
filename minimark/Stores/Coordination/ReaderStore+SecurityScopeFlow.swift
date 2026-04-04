import Foundation

extension ReaderStore {
    func activateFileSecurityScope(for url: URL, reason: String) {
        scopeContext.fileToken?.endAccess()
        scopeContext.fileToken = securityScope.beginAccess(to: url)
        if scopeContext.fileToken?.didStartAccess == true {
            scopeContext.accessibleFileURL = url
            scopeContext.accessibleFileURLSource = "fileScope"
        }
    }

    func bindFolderWatchSessionIfNeeded(_ session: ReaderFolderWatchSession?) {
        guard let session else {
            return
        }

        setActiveFolderWatchSession(normalizedFolderWatchSession(session))
    }

    func ensureFolderWatchAccessIfNeeded(for fileURL: URL, reason: String) {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL) else {
            return
        }

        if scopeContext.folderToken?.didStartAccess == true {
            return
        }

        let accessURL = resolvedWatchedFolderAccessURL(for: activeFolderWatchSession)
        scopeContext.folderToken?.endAccess()
        scopeContext.folderToken = securityScope.beginAccess(to: accessURL)
    }

    func effectiveAccessibleFileURL(for url: URL, reason: String) -> URL {
        let normalizedURL = Self.normalizedFileURL(url)
        ensureFolderWatchAccessIfNeeded(for: normalizedURL, reason: reason)

        if let fileToken = scopeContext.fileToken,
           fileToken.didStartAccess,
           Self.normalizedFileURL(fileToken.url) == normalizedURL {
            scopeContext.accessibleFileURL = fileToken.url
            scopeContext.accessibleFileURLSource = "fileScope"
            return fileToken.url
        }

        if let accessibleFileURL = scopeContext.accessibleFileURL,
           scopeContext.accessibleFileURLSource == "fileScope",
           Self.normalizedFileURL(accessibleFileURL) == normalizedURL {
            return accessibleFileURL
        }

        if let folderScopedFileURL = folderScopedAccessibleFileURL(for: normalizedURL) {
            scopeContext.accessibleFileURL = folderScopedFileURL
            scopeContext.accessibleFileURLSource = "folderScopeChildURL"
            return folderScopedFileURL
        }

        deriveFileSecurityScopeFromFolderIfNeeded(for: normalizedURL, reason: reason)

        if let fileToken = scopeContext.fileToken,
           fileToken.didStartAccess,
           Self.normalizedFileURL(fileToken.url) == normalizedURL {
            scopeContext.accessibleFileURL = fileToken.url
            scopeContext.accessibleFileURLSource = "fileScope"
            return fileToken.url
        }

        return normalizedURL
    }

    func folderScopedAccessibleFileURL(for fileURL: URL) -> URL? {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL),
              let folderToken = scopeContext.folderToken,
              folderToken.didStartAccess else {
            return nil
        }

        let normalizedFileURL = Self.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
        let watchedFolderPath = normalizedWatchedFolderURL.path
        let filePath = normalizedFileURL.path

        guard filePath.hasPrefix(watchedFolderPath) else {
            return nil
        }

        let relativePath = filePath.dropFirst(watchedFolderPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            return folderToken.url
        }

        return URL(fileURLWithPath: relativePath, relativeTo: folderToken.url).standardizedFileURL
    }

    func tryReauthorizeWatchedFolderIfNeeded(after error: Error, for fileURL: URL) -> Bool {
        guard isPermissionDeniedWriteError(error),
              let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL) else {
            return false
        }

        let watchedFolderURL = Self.normalizedFileURL(activeFolderWatchSession.folderURL)
        logSaveInfo(
            "watched-folder reauthorization requested: file=\(redactedPathText(for: fileURL)) watchedFolder=\(redactedPathText(for: watchedFolderURL))"
        )

        guard let selectedFolderURL = requestWatchedFolderReauthorization(watchedFolderURL) else {
            logSaveError(
                "watched-folder reauthorization cancelled: \(saveLogContext(for: fileURL))"
            )
            return false
        }

        let normalizedSelectedFolderURL = Self.normalizedFileURL(selectedFolderURL)
        guard normalizedSelectedFolderURL == watchedFolderURL else {
            logSaveError(
                "watched-folder reauthorization mismatched selection: requested=\(redactedPathText(for: watchedFolderURL)) selected=\(redactedPathText(for: normalizedSelectedFolderURL))"
            )
            return false
        }

        settingsStore.addRecentWatchedFolder(selectedFolderURL, options: activeFolderWatchSession.options)
        scopeContext.folderToken?.endAccess()
        scopeContext.folderToken = securityScope.beginAccess(to: selectedFolderURL)
        setActiveFolderWatchSession(
            ReaderFolderWatchSession(
                folderURL: watchedFolderURL,
                options: activeFolderWatchSession.options,
                startedAt: activeFolderWatchSession.startedAt
            )
        )
        scopeContext.fileToken?.endAccess()
        scopeContext.fileToken = nil
        scopeContext.accessibleFileURL = nil
        scopeContext.accessibleFileURLSource = nil

        logSaveInfo(
            "watched-folder reauthorization completed: watchedFolder=\(redactedPathText(for: watchedFolderURL)) selected=\(redactedPathText(for: normalizedSelectedFolderURL)) started=\(scopeContext.folderToken?.didStartAccess == true)"
        )

        return scopeContext.folderToken?.didStartAccess == true
    }

    func isPermissionDeniedWriteError(_ error: Error) -> Bool {
        let resolvedError: NSError
        if case let ReaderError.fileWriteFailed(_, underlying) = error {
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

    func deriveFileSecurityScopeFromFolderIfNeeded(for fileURL: URL, reason: String) {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL),
              let folderToken = scopeContext.folderToken,
              folderToken.didStartAccess else {
            return
        }

        do {
            let folderScopedFileURL = folderScopedAccessibleFileURL(for: fileURL) ?? fileURL
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
                logSaveInfo(
                    "bookmark stale while deriving file scope: reason=\(reason) file=\(redactedPathText(for: fileURL))"
                )
            }
            activateFileSecurityScope(for: scopedFileURL, reason: "\(reason)-derivedFromFolder")
        } catch {
            logSaveInfo(
                "failed deriving file scope from folder: reason=\(reason) file=\(redactedPathText(for: fileURL)) error=\(error.localizedDescription)"
            )
        }
    }

    func resolvedWatchedFolderAccessURL(for session: ReaderFolderWatchSession) -> URL {
        settingsStore.resolvedRecentWatchedFolderURL(matching: session.folderURL) ?? session.folderURL
    }

    func watchedFolderSession(_ session: ReaderFolderWatchSession, appliesTo fileURL: URL) -> Bool {
        let normalizedFileURL = Self.normalizedFileURL(fileURL)
        let normalizedWatchedFolderURL = Self.normalizedFileURL(session.folderURL)

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

    func normalizedFolderWatchSession(_ session: ReaderFolderWatchSession) -> ReaderFolderWatchSession {
        ReaderFolderWatchSession(
            folderURL: Self.normalizedFileURL(session.folderURL),
            options: session.options,
            startedAt: session.startedAt
        )
    }

    // MARK: - Trusted Image Folder Access

    func activateTrustedImageFolderAccessIfNeeded(for directoryURL: URL?) {
        guard let directoryURL else { return }

        // Skip if folder watch already grants access to this directory
        if let activeFolderWatchSession,
           watchedFolderSession(activeFolderWatchSession, appliesTo: directoryURL.appendingPathComponent("dummy")),
           scopeContext.folderToken?.didStartAccess == true {
            return
        }

        // Skip if already active for the right directory (directory is within token's scope)
        if let directoryToken = scopeContext.directoryToken,
           directoryToken.didStartAccess,
           Self.normalizedFileURL(directoryURL)
               .path.hasPrefix(Self.normalizedFileURL(URL(fileURLWithPath: directoryToken.url.path)).path) {
            return
        }

        guard let resolvedURL = settingsStore.resolvedTrustedImageFolderURL(
            containing: directoryURL.appendingPathComponent("dummy")
        ) else {
            return
        }

        scopeContext.directoryToken?.endAccess()
        scopeContext.directoryToken = securityScope.beginAccess(to: resolvedURL)
        logSaveInfo(
            "trusted image folder scope activated: directory=\(redactedPathText(for: directoryURL)) started=\(scopeContext.directoryToken?.didStartAccess == true)"
        )
    }

    func grantImageDirectoryAccess(folderURL: URL) {
        settingsStore.addTrustedImageFolder(folderURL)

        scopeContext.directoryToken?.endAccess()
        scopeContext.directoryToken = securityScope.beginAccess(to: folderURL)
        logSaveInfo(
            "image directory access granted: folder=\(redactedPathText(for: folderURL)) started=\(scopeContext.directoryToken?.didStartAccess == true)"
        )

        do {
            try renderCurrentMarkdownImmediately()
        } catch {
            logSaveError("re-render after granting image access failed: \(error.localizedDescription)")
        }
    }
}
