import Foundation

@MainActor
final class SourceEditingFlow {
    private let document: ReaderDocumentController
    private let sourceEditingController: ReaderSourceEditingController
    private let externalChange: ReaderExternalChangeController
    private let renderingController: ReaderRenderingController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let persister: SourceDraftPersister
    private let reloader: DocumentReloader
    private let saveLogFormatter: SaveLogFormatter
    private let onError: @MainActor (Error) -> Void

    init(
        document: ReaderDocumentController,
        sourceEditingController: ReaderSourceEditingController,
        externalChange: ReaderExternalChangeController,
        renderingController: ReaderRenderingController,
        folderWatchDispatcher: FolderWatchDispatcher,
        persister: SourceDraftPersister,
        reloader: DocumentReloader,
        saveLogFormatter: SaveLogFormatter,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.document = document
        self.sourceEditingController = sourceEditingController
        self.externalChange = externalChange
        self.renderingController = renderingController
        self.folderWatchDispatcher = folderWatchDispatcher
        self.persister = persister
        self.reloader = reloader
        self.saveLogFormatter = saveLogFormatter
        self.onError = onError
    }

    func startEditing() {
        let wasEditing = sourceEditingController.isSourceEditing
        sourceEditingController.startEditing(
            savedMarkdown: document.savedMarkdown,
            hasOpenDocument: document.hasOpenDocument,
            isCurrentFileMissing: document.isCurrentFileMissing
        )
        if !wasEditing && sourceEditingController.isSourceEditing {
            document.sourceMarkdown = document.savedMarkdown
            document.clearLastError()
        }
    }

    func updateDraft(_ markdown: String) {
        guard sourceEditingController.isSourceEditing else { return }

        let unsavedChangedRegions = renderingController.computeChangedRegions(
            diffBaselineMarkdown: document.savedMarkdown,
            newMarkdown: markdown
        )
        sourceEditingController.updateDraft(
            markdown,
            savedMarkdown: document.savedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions
        )
        document.sourceMarkdown = markdown

        renderingController.scheduleDraftPreviewRender(
            sourceMarkdown: document.sourceMarkdown,
            changedRegions: document.changedRegions,
            unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
            fileURL: document.fileURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
    }

    func save() {
        guard sourceEditingController.isSourceEditing,
              let draftMarkdown = sourceEditingController.draftMarkdown,
              let fileURL = document.fileURL else {
            saveLogFormatter.logError(
                "save requested without active editable document: \(saveLogFormatter.saveContext(for: document.fileURL))"
            )
            onError(AppError.noOpenFileInReader)
            return
        }

        do {
            saveLogFormatter.logInfo(
                "save requested: \(saveLogFormatter.saveContext(for: fileURL)) draftUTF8Bytes=\(draftMarkdown.utf8.count)"
            )
            renderingController.cancelPendingDraftPreviewRender()
            let diffBaselineMarkdown = document.savedMarkdown
            try persister.persist(
                draftMarkdown,
                to: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                recoveryAttempted: false
            )
        } catch {
            onError(error)
        }
    }

    func discard() {
        guard sourceEditingController.isSourceEditing else { return }

        if externalChange.hasUnacknowledgedExternalChange {
            reloader.reload(
                at: document.fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: true
            )
            return
        }

        sourceEditingController.finishSession(markdown: document.savedMarkdown)
        document.sourceMarkdown = document.savedMarkdown

        do {
            try renderingController.renderImmediately(
                sourceMarkdown: document.sourceMarkdown,
                changedRegions: document.changedRegions,
                unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
                fileURL: document.fileURL,
                folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
            document.clearLastError()
        } catch {
            onError(error)
        }
    }
}
