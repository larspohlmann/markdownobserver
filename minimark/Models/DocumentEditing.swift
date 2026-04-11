import Foundation

struct DocumentEditing {
    var documentViewMode: ReaderDocumentViewMode = .preview
    var isSourceEditing: Bool = false
    var hasUnsavedDraftChanges: Bool = false
    var draftMarkdown: String?
    var sourceEditorSeedMarkdown: String = ""
    var unsavedChangedRegions: [ChangedRegion] = []
    var pendingSavedDraftDiffBaselineMarkdown: String?

    static let empty = DocumentEditing()

    var canSaveSourceDraft: Bool { isSourceEditing && hasUnsavedDraftChanges }
    var canDiscardSourceDraft: Bool { isSourceEditing }
}
