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
        self.fileURL = store.document.fileURL
        self.fileDisplayName = store.document.fileDisplayName
        self.isSourceEditing = store.sourceEditingController.isSourceEditing
        self.hasUnsavedDraftChanges = store.sourceEditingController.hasUnsavedDraftChanges
        self.canSaveSourceDraft = store.sourceEditingController.canSaveSourceDraft
        self.canDiscardSourceDraft = store.sourceEditingController.canDiscardSourceDraft
        self.statusBarTimestamp = store.statusBarTimestamp
        self.isCurrentFileMissing = store.document.isCurrentFileMissing
    }
}
