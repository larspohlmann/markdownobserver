import Foundation
import Observation

@MainActor
@Observable
final class SourceEditingController {
    var documentViewMode: ReaderDocumentViewMode = .preview
    var isSourceEditing: Bool = false
    var hasUnsavedDraftChanges: Bool = false
    var draftMarkdown: String?
    var sourceEditorSeedMarkdown: String = ""
    var unsavedChangedRegions: [ChangedRegion] = []
    var pendingSavedDraftDiffBaselineMarkdown: String?

    var canSaveSourceDraft: Bool { isSourceEditing && hasUnsavedDraftChanges }
    var canDiscardSourceDraft: Bool { isSourceEditing }

    // MARK: - Session lifecycle

    func startEditing(
        savedMarkdown: String,
        hasOpenDocument: Bool,
        isCurrentFileMissing: Bool
    ) {
        guard hasOpenDocument && !isCurrentFileMissing && !isSourceEditing else { return }
        applyTransition(
            draftMarkdown: savedMarkdown,
            sourceEditorSeedMarkdown: savedMarkdown,
            unsavedChangedRegions: [],
            isSourceEditing: true,
            hasUnsavedDraftChanges: false
        )
    }

    func updateDraft(
        _ markdown: String,
        savedMarkdown: String,
        unsavedChangedRegions: [ChangedRegion]
    ) {
        guard isSourceEditing else { return }
        applyTransition(
            draftMarkdown: markdown,
            sourceEditorSeedMarkdown: sourceEditorSeedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions,
            isSourceEditing: true,
            hasUnsavedDraftChanges: markdown != savedMarkdown
        )
    }

    func finishSession(markdown: String) {
        applyTransition(
            draftMarkdown: nil,
            sourceEditorSeedMarkdown: markdown,
            unsavedChangedRegions: [],
            isSourceEditing: false,
            hasUnsavedDraftChanges: false
        )
    }

    func reset() {
        draftMarkdown = nil
        isSourceEditing = false
        hasUnsavedDraftChanges = false
        sourceEditorSeedMarkdown = ""
        unsavedChangedRegions = []
        pendingSavedDraftDiffBaselineMarkdown = nil
    }

    func applyLoadedDocumentState(
        markdown: String,
        resetDocumentViewMode: Bool
    ) {
        draftMarkdown = nil
        pendingSavedDraftDiffBaselineMarkdown = nil
        sourceEditorSeedMarkdown = markdown
        if resetDocumentViewMode {
            documentViewMode = .preview
        }
        unsavedChangedRegions = []
        isSourceEditing = false
        hasUnsavedDraftChanges = false
    }

    // MARK: - View mode

    func setViewMode(_ mode: ReaderDocumentViewMode, hasOpenDocument: Bool) {
        guard hasOpenDocument else {
            documentViewMode = .preview
            return
        }
        guard documentViewMode != mode else { return }
        documentViewMode = mode
    }

    func toggleViewMode() {
        documentViewMode = documentViewMode.next
    }

    // MARK: - Private

    private func applyTransition(
        draftMarkdown: String?,
        sourceEditorSeedMarkdown: String,
        unsavedChangedRegions: [ChangedRegion],
        isSourceEditing: Bool,
        hasUnsavedDraftChanges: Bool
    ) {
        self.draftMarkdown = draftMarkdown
        self.sourceEditorSeedMarkdown = sourceEditorSeedMarkdown
        self.unsavedChangedRegions = unsavedChangedRegions
        self.isSourceEditing = isSourceEditing
        self.hasUnsavedDraftChanges = hasUnsavedDraftChanges
    }
}
