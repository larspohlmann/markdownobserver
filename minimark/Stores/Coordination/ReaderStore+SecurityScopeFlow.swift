import Foundation

extension ReaderStore {
    func activateFileSecurityScope(for url: URL, reason: String) {
        securityScopeToken?.endAccess()
        securityScopeToken = securityScope.beginAccess(to: url)
        if securityScopeToken?.didStartAccess == true {
            currentAccessibleFileURL = url
            currentAccessibleFileURLSource = "fileScope"
        }
        logSaveInfo(
            "file scope updated: reason=\(reason) url=\(redactedPathText(for: url)) started=\(securityScopeToken?.didStartAccess == true)"
        )
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

        if folderSecurityScopeToken?.didStartAccess == true {
            return
        }

        let accessURL = resolvedWatchedFolderAccessURL(for: activeFolderWatchSession)
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = securityScope.beginAccess(to: accessURL)
        logSaveInfo(
            "folder scope updated: reason=\(reason) watchedFolder=\(redactedPathText(for: activeFolderWatchSession.folderURL)) accessURL=\(redactedPathText(for: accessURL)) started=\(folderSecurityScopeToken?.didStartAccess == true) appliesToFile=\(redactedPathText(for: fileURL))"
        )
    }

    func effectiveAccessibleFileURL(for url: URL, reason: String) -> URL {
        let normalizedURL = Self.normalizedFileURL(url)
        ensureFolderWatchAccessIfNeeded(for: normalizedURL, reason: reason)

        if let securityScopeToken,
           securityScopeToken.didStartAccess,
           Self.normalizedFileURL(securityScopeToken.url) == normalizedURL {
            currentAccessibleFileURL = securityScopeToken.url
            currentAccessibleFileURLSource = "fileScope"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(redactedPathText(for: normalizedURL)) accessURL=\(redactedPathText(for: securityScopeToken.url)) source=fileScope"
            )
            return securityScopeToken.url
        }

        if let currentAccessibleFileURL,
           currentAccessibleFileURLSource == "fileScope",
           Self.normalizedFileURL(currentAccessibleFileURL) == normalizedURL {
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(redactedPathText(for: normalizedURL)) accessURL=\(redactedPathText(for: currentAccessibleFileURL)) source=cachedFileScope"
            )
            return currentAccessibleFileURL
        }

        if let folderScopedFileURL = folderScopedAccessibleFileURL(for: normalizedURL) {
            currentAccessibleFileURL = folderScopedFileURL
            currentAccessibleFileURLSource = "folderScopeChildURL"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(redactedPathText(for: normalizedURL)) accessURL=\(redactedPathText(for: folderScopedFileURL)) source=folderScopeChildURL"
            )
            return folderScopedFileURL
        }

        deriveFileSecurityScopeFromFolderIfNeeded(for: normalizedURL, reason: reason)

        if let securityScopeToken,
           securityScopeToken.didStartAccess,
           Self.normalizedFileURL(securityScopeToken.url) == normalizedURL {
            currentAccessibleFileURL = securityScopeToken.url
            currentAccessibleFileURLSource = "fileScope"
            logSaveInfo(
                "effective file access: reason=\(reason) file=\(redactedPathText(for: normalizedURL)) accessURL=\(redactedPathText(for: securityScopeToken.url)) source=fileScopeDerived"
            )
            return securityScopeToken.url
        }

        logSaveInfo(
            "effective file access: reason=\(reason) file=\(redactedPathText(for: normalizedURL)) accessURL=\(redactedPathText(for: normalizedURL)) source=plainURL"
        )
        return normalizedURL
    }

    func folderScopedAccessibleFileURL(for fileURL: URL) -> URL? {
        guard let activeFolderWatchSession,
              watchedFolderSession(activeFolderWatchSession, appliesTo: fileURL),
              let folderSecurityScopeToken,
              folderSecurityScopeToken.didStartAccess else {
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
            return folderSecurityScopeToken.url
        }

        return URL(fileURLWithPath: relativePath, relativeTo: folderSecurityScopeToken.url).standardizedFileURL
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
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = securityScope.beginAccess(to: selectedFolderURL)
        setActiveFolderWatchSession(
            ReaderFolderWatchSession(
                folderURL: watchedFolderURL,
                options: activeFolderWatchSession.options,
                startedAt: activeFolderWatchSession.startedAt
            )
        )
        securityScopeToken?.endAccess()
        securityScopeToken = nil
        currentAccessibleFileURL = nil
        currentAccessibleFileURLSource = nil

        logSaveInfo(
            "watched-folder reauthorization completed: watchedFolder=\(redactedPathText(for: watchedFolderURL)) selected=\(redactedPathText(for: normalizedSelectedFolderURL)) started=\(folderSecurityScopeToken?.didStartAccess == true)"
        )

        return folderSecurityScopeToken?.didStartAccess == true
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
              let folderSecurityScopeToken,
              folderSecurityScopeToken.didStartAccess else {
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
}
