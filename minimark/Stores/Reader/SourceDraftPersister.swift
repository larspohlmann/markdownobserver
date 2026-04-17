import Foundation
import OSLog

@MainActor
final class SourceDraftPersister {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "SourceDraftPersister"
    )

    private let document: ReaderDocumentController
    private let sourceEditingController: ReaderSourceEditingController
    private let externalChange: ReaderExternalChangeController
    private let renderingController: ReaderRenderingController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let securityScopeResolver: SecurityScopeResolver
    private let fileIO: DocumentIO
    private let saveLogFormatter: SaveLogFormatter

    init(
        document: ReaderDocumentController,
        sourceEditingController: ReaderSourceEditingController,
        externalChange: ReaderExternalChangeController,
        renderingController: ReaderRenderingController,
        folderWatchDispatcher: FolderWatchDispatcher,
        securityScopeResolver: SecurityScopeResolver,
        fileIO: DocumentIO,
        saveLogFormatter: SaveLogFormatter
    ) {
        self.document = document
        self.sourceEditingController = sourceEditingController
        self.externalChange = externalChange
        self.renderingController = renderingController
        self.folderWatchDispatcher = folderWatchDispatcher
        self.securityScopeResolver = securityScopeResolver
        self.fileIO = fileIO
        self.saveLogFormatter = saveLogFormatter
    }

    func persist(
        _ draftMarkdown: String,
        to fileURL: URL,
        diffBaselineMarkdown: String,
        recoveryAttempted: Bool
    ) throws {
        do {
            let accessibleURL = securityScopeResolver.effectiveAccessibleFileURL(
                for: fileURL, reason: "write", folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
            try fileIO.write(draftMarkdown, to: accessibleURL)
            document.savedMarkdown = draftMarkdown
            sourceEditingController.finishSession(markdown: draftMarkdown)
            document.sourceMarkdown = draftMarkdown
            document.changedRegions = renderingController.computeChangedRegions(
                diffBaselineMarkdown: diffBaselineMarkdown,
                newMarkdown: draftMarkdown
            )
            document.fileLastModifiedAt = fileIO.modificationDate(for: fileURL)
            sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = document.changedRegions.isEmpty ? nil : diffBaselineMarkdown
            externalChange.clear()
            document.isCurrentFileMissing = false
            try renderingController.renderImmediately(
                sourceMarkdown: document.sourceMarkdown,
                changedRegions: document.changedRegions,
                unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
                fileURL: document.fileURL,
                folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
            document.lastError = nil
            let modifiedAtDescription = document.fileLastModifiedAt?.description ?? "nil"
            saveLogFormatter.logInfo(
                "save succeeded: \(saveLogFormatter.saveContext(for: fileURL)) modifiedAt=\(modifiedAtDescription) recoveryAttempted=\(recoveryAttempted)"
            )
        } catch {
            saveLogFormatter.logError(
                "save failed: \(saveLogFormatter.saveContext(for: fileURL)) error=\(error.localizedDescription) recoveryAttempted=\(recoveryAttempted)"
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

            saveLogFormatter.logInfo(
                "save retrying after watched-folder reauthorization: \(saveLogFormatter.saveContext(for: fileURL))"
            )
            try persist(
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
            try renderingController.renderImmediately(
                sourceMarkdown: document.sourceMarkdown,
                changedRegions: document.changedRegions,
                unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
                fileURL: document.fileURL,
                folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
        } catch {
            saveLogFormatter.logError("re-render after granting image access failed: \(error.localizedDescription)")
        }
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
            loaded = try fileIO.load(at: accessibleURL)
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
        document.changedRegions = renderingController.computeChangedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        sourceEditingController.unsavedChangedRegions = []
        sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = nil
        return true
    }
}
