import Foundation

struct ReaderSourceEditingTransition {
    let draftMarkdown: String?
    let sourceMarkdown: String
    let sourceEditorSeedMarkdown: String
    let unsavedChangedRegions: [ChangedRegion]
    let isSourceEditing: Bool
    let hasUnsavedDraftChanges: Bool
}

struct ReaderSourceEditingCoordinator {
    func canStart(
        hasOpenDocument: Bool,
        isCurrentFileMissing: Bool,
        isSourceEditing: Bool
    ) -> Bool {
        hasOpenDocument && !isCurrentFileMissing && !isSourceEditing
    }

    func canUpdate(isSourceEditing: Bool) -> Bool {
        isSourceEditing
    }

    func canDiscard(isSourceEditing: Bool) -> Bool {
        isSourceEditing
    }

    func beginSession(markdown: String) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: markdown,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: markdown,
            unsavedChangedRegions: [],
            isSourceEditing: true,
            hasUnsavedDraftChanges: false
        )
    }

    func updateDraft(
        markdown: String,
        sourceEditorSeedMarkdown: String,
        diffBaselineMarkdown: String,
        unsavedChangedRegions: [ChangedRegion]
    ) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: markdown,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: sourceEditorSeedMarkdown,
            unsavedChangedRegions: unsavedChangedRegions,
            isSourceEditing: true,
            hasUnsavedDraftChanges: markdown != diffBaselineMarkdown
        )
    }

    func finishSession(markdown: String) -> ReaderSourceEditingTransition {
        ReaderSourceEditingTransition(
            draftMarkdown: nil,
            sourceMarkdown: markdown,
            sourceEditorSeedMarkdown: markdown,
            unsavedChangedRegions: [],
            isSourceEditing: false,
            hasUnsavedDraftChanges: false
        )
    }
}
