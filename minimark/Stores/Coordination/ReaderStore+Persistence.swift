import Foundation
import OSLog

extension ReaderStore {
    func persistSourceDraft(
        _ draftMarkdown: String,
        to fileURL: URL,
        diffBaselineMarkdown: String,
        recoveryAttempted: Bool
    ) throws {
        do {
            let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
                for: fileURL, reason: "write", folderWatchSession: activeFolderWatchSession
            )
            try file.io.write(draftMarkdown, to: accessibleURL)
            document.savedMarkdown = draftMarkdown
            sourceEditingController.finishSession(markdown: draftMarkdown)
            document.sourceMarkdown = draftMarkdown
            document.changedRegions = changedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            document.fileLastModifiedAt = file.io.modificationDate(for: fileURL)
            sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = document.changedRegions.isEmpty ? nil : diffBaselineMarkdown
            externalChange.clear()
            document.isCurrentFileMissing = false
            try renderCurrentMarkdownImmediately()
            document.lastError = nil
            let modifiedAtDescription = fileLastModifiedAt?.description ?? "nil"
            logSaveInfo(
                "save succeeded: \(saveLogContext(for: fileURL)) modifiedAt=\(modifiedAtDescription) recoveryAttempted=\(recoveryAttempted)"
            )
        } catch {
            logSaveError(
                "save failed: \(saveLogContext(for: fileURL)) error=\(error.localizedDescription) recoveryAttempted=\(recoveryAttempted)"
            )

            guard !recoveryAttempted else {
                throw error
            }

            let result = securityScopeResolver.tryReauthorizeWatchedFolder(
                after: error, for: fileURL, folderWatchSession: activeFolderWatchSession
            )
            guard result.succeeded else {
                throw error
            }
            if let updatedSession = result.updatedSession {
                setActiveFolderWatchSession(updatedSession)
            }

            logSaveInfo(
                "save retrying after watched-folder reauthorization: \(saveLogContext(for: fileURL))"
            )
            try persistSourceDraft(
                draftMarkdown,
                to: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                recoveryAttempted: true
            )
        }
    }

    func grantImageDirectoryAccess(folderURL: URL) {
        securityScopeResolver.grantImageDirectoryAccess(folderURL: folderURL)

        do {
            try renderCurrentMarkdownImmediately()
        } catch {
            logSaveError("re-render after granting image access failed: \(error.localizedDescription)")
        }
    }

    func changedRegions(
        diffBaselineMarkdown: String?,
        newMarkdown: String
    ) -> [ChangedRegion] {
        guard let diffBaselineMarkdown else {
            return []
        }

        return rendering.differ.computeChangedRegions(
            oldMarkdown: diffBaselineMarkdown,
            newMarkdown: newMarkdown
        )
    }

    func handlePendingSavedDraftChangeIfNeeded() -> Bool {
        guard let diffBaselineMarkdown = sourceEditingController.pendingSavedDraftDiffBaselineMarkdown,
              let fileURL,
              !isSourceEditing else {
            return false
        }

        let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
            for: fileURL, reason: "read", folderWatchSession: activeFolderWatchSession
        )
        let loaded: (markdown: String, modificationDate: Date)
        do {
            loaded = try file.io.load(at: accessibleURL)
        } catch {
            let nsError = error as NSError
            Self.logger.error(
                "draft baseline load failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .private)"
            )
            sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        guard loaded.markdown == sourceMarkdown else {
            sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = nil
            return false
        }

        document.fileLastModifiedAt = loaded.modificationDate
        document.changedRegions = changedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        sourceEditingController.unsavedChangedRegions = []
        sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = nil
        return true
    }

    func loadMarkdownFile(at url: URL) throws -> (markdown: String, modificationDate: Date) {
        let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
            for: url, reason: "read", folderWatchSession: activeFolderWatchSession
        )
        return try file.io.load(at: accessibleURL)
    }

    // MARK: - Logging

    func saveLogContext(for url: URL?) -> String {
        let filePath = redactedPathText(for: url)
        let watchedFolderPath = redactedPathText(for: activeFolderWatchSession?.folderURL)
        let ctx = securityScopeResolver.context
        let fileScopeURL = redactedPathText(for: ctx.fileToken?.url)
        let folderScopeURL = redactedPathText(for: ctx.folderToken?.url)
        let accessibleFilePath = redactedPathText(for: ctx.accessibleFileURL)
        return "file=\(filePath) origin=\(document.currentOpenOrigin.rawValue) editing=\(isSourceEditing) unsaved=\(hasUnsavedDraftChanges) fileScope=\(ctx.fileToken != nil) fileScopeStarted=\(ctx.fileToken?.didStartAccess == true) fileScopeURL=\(fileScopeURL) folderScope=\(ctx.folderToken != nil) folderScopeStarted=\(ctx.folderToken?.didStartAccess == true) folderScopeURL=\(folderScopeURL) accessibleFileURL=\(accessibleFilePath) watchedFolder=\(watchedFolderPath)"
    }

    func redactedPathText(for url: URL?) -> String {
        guard let url else {
            return "none"
        }

        let normalizedURL = Self.normalizedFileURL(url)
        let name = normalizedURL.lastPathComponent.isEmpty ? "root" : normalizedURL.lastPathComponent
        let pathHash = String(normalizedURL.path.hashValue.magnitude, radix: 16)
        return "\(name)#\(pathHash)"
    }

    func logSaveInfo(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
    }

    func logSaveError(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
    }
}
