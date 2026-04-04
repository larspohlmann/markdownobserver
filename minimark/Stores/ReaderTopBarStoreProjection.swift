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
        self.fileURL = store.fileURL
        self.fileDisplayName = store.fileDisplayName
        self.isSourceEditing = store.isSourceEditing
        self.hasUnsavedDraftChanges = store.hasUnsavedDraftChanges
        self.canSaveSourceDraft = store.canSaveSourceDraft
        self.canDiscardSourceDraft = store.canDiscardSourceDraft
        self.statusBarTimestamp = store.statusBarTimestamp
        self.isCurrentFileMissing = store.isCurrentFileMissing
    }
}
