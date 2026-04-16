import Foundation

struct ReaderTopBarStoreProjection {
    let fileURL: URL?
    let fileDisplayName: String
    let isSourceEditing: Bool
    let hasUnsavedDraftChanges: Bool
    let canSaveSourceDraft: Bool
    let canDiscardSourceDraft: Bool
    let statusBarTimestamp: ReaderStatusBarTimestamp?
    let isCurrentFileMissing: Bool

    @MainActor
    init(store: ReaderStore) {
        self.init(document: store.document, sourceEditing: store.sourceEditingController)
    }

    @MainActor
    init(document: ReaderDocumentController, sourceEditing: ReaderSourceEditingController) {
        self.fileURL = document.fileURL
        self.fileDisplayName = document.fileDisplayName
        self.isSourceEditing = sourceEditing.isSourceEditing
        self.hasUnsavedDraftChanges = sourceEditing.hasUnsavedDraftChanges
        self.canSaveSourceDraft = sourceEditing.canSaveSourceDraft
        self.canDiscardSourceDraft = sourceEditing.canDiscardSourceDraft
        self.statusBarTimestamp = document.fileLastModifiedAt.map { .lastModified($0) }
        self.isCurrentFileMissing = document.isCurrentFileMissing
    }
}
