import Foundation

extension ReaderStore {
    func startEditingSource() {
        guard sourceEditingCoordinator.canStart(
            hasOpenDocument: hasOpenDocument,
            isCurrentFileMissing: isCurrentFileMissing,
            isSourceEditing: isSourceEditing
        ) else {
            return
        }

        let transition = sourceEditingCoordinator.beginSession(markdown: content.savedMarkdown)
        applySourceEditingTransition(transition)
        clearLastError()
    }

    func updateSourceDraft(_ markdown: String) {
        guard sourceEditingCoordinator.canUpdate(isSourceEditing: isSourceEditing) else {
            return
        }

        let unsavedChangedRegions = changedRegions(
            diffBaselineMarkdown: content.savedMarkdown,
            newMarkdown: markdown
        )
        let transition = sourceEditingCoordinator.updateDraft(
            markdown: markdown,
            sourceEditorSeedMarkdown: sourceEditorSeedMarkdown,
            diffBaselineMarkdown: content.savedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions
        )
        applySourceEditingTransition(transition)

        scheduleDraftPreviewRender()
    }

    func saveSourceDraft() {
        guard isSourceEditing,
              let draftMarkdown = editing.draftMarkdown,
              let fileURL else {
            logSaveError("save requested without active editable document: \(saveLogContext(for: fileURL))")
            handle(ReaderError.noOpenFileInReader)
            return
        }

        do {
            logSaveInfo(
                "save requested: \(saveLogContext(for: fileURL)) draftUTF8Bytes=\(draftMarkdown.utf8.count)"
            )
            cancelPendingDraftPreviewRender()
            let diffBaselineMarkdown = content.savedMarkdown
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
        guard sourceEditingCoordinator.canDiscard(isSourceEditing: isSourceEditing) else {
            return
        }

        if hasUnacknowledgedExternalChange {
            reloadCurrentFile(
                at: fileURL,
                diffBaselineMarkdown: nil,
                acknowledgeExternalChange: true
            )
            return
        }

        let transition = sourceEditingCoordinator.finishSession(markdown: content.savedMarkdown)
        applySourceEditingTransition(transition)

        do {
            try renderCurrentMarkdownImmediately()
            clearLastError()
        } catch {
            handle(error)
        }
    }
}
