import Foundation

extension ReaderStore {
    func startEditingSource() {
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

    func updateSourceDraft(_ markdown: String) {
        guard sourceEditingController.isSourceEditing else { return }

        let unsavedChangedRegions = changedRegions(
            diffBaselineMarkdown: document.savedMarkdown,
            newMarkdown: markdown
        )
        sourceEditingController.updateDraft(
            markdown,
            savedMarkdown: document.savedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions
        )
        document.sourceMarkdown = markdown

        scheduleDraftPreviewRender()
    }

    func saveSourceDraft() {
        guard sourceEditingController.isSourceEditing,
              let draftMarkdown = sourceEditingController.draftMarkdown,
              let fileURL = document.fileURL else {
            logSaveError("save requested without active editable document: \(saveLogContext(for: document.fileURL))")
            handle(ReaderError.noOpenFileInReader)
            return
        }

        do {
            logSaveInfo(
                "save requested: \(saveLogContext(for: fileURL)) draftUTF8Bytes=\(draftMarkdown.utf8.count)"
            )
            cancelPendingDraftPreviewRender()
            let diffBaselineMarkdown = document.savedMarkdown
            try persistSourceDraft(
                draftMarkdown,
                to: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                recoveryAttempted: false
            )
        } catch {
            handle(error)
        }
    }

    func discardSourceDraft() {
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
            try renderCurrentMarkdownImmediately()
            document.clearLastError()
        } catch {
            handle(error)
        }
    }
}
