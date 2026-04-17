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
                for: fileURL, reason: "write", folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
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
            let modifiedAtDescription = document.fileLastModifiedAt?.description ?? "nil"
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
                after: error, for: fileURL, folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
            guard result.succeeded else {
                throw error
            }
            if let updatedSession = result.updatedSession {
                folderWatchDispatcher.setSession(updatedSession)
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
              let fileURL = document.fileURL,
              !sourceEditingController.isSourceEditing else {
            return false
        }

        let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
            for: fileURL, reason: "read", folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
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

        guard loaded.markdown == document.sourceMarkdown else {
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
        try fileLoader.load(
            at: url,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
    }

    // MARK: - Logging

    func saveLogContext(for url: URL?) -> String {
        saveLogFormatter.saveContext(for: url)
    }

    func redactedPathText(for url: URL?) -> String {
        saveLogFormatter.redactedPath(for: url)
    }

    func logSaveInfo(_ message: String) {
        saveLogFormatter.logInfo(message)
    }

    func logSaveError(_ message: String) {
        saveLogFormatter.logError(message)
    }
}
