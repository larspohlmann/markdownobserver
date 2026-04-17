import Foundation

struct TopBarStoreProjection {
    let fileURL: URL?
    let fileDisplayName: String
    let isSourceEditing: Bool
    let hasUnsavedDraftChanges: Bool
    let canSaveSourceDraft: Bool
    let canDiscardSourceDraft: Bool
    let statusBarTimestamp: StatusBarTimestamp?
    let isCurrentFileMissing: Bool

    @MainActor
    init(store: DocumentStore) {
        self.init(
            document: store.document,
            sourceEditing: store.sourceEditingController,
            statusBarTimestamp: store.statusBarTimestamp
        )
    }

    @MainActor
    init(
        document: DocumentController,
        sourceEditing: SourceEditingController,
        statusBarTimestamp: StatusBarTimestamp?
    ) {
        self.fileURL = document.fileURL
        self.fileDisplayName = document.fileDisplayName
        self.isSourceEditing = sourceEditing.isSourceEditing
        self.hasUnsavedDraftChanges = sourceEditing.hasUnsavedDraftChanges
        self.canSaveSourceDraft = sourceEditing.canSaveSourceDraft
        self.canDiscardSourceDraft = sourceEditing.canDiscardSourceDraft
        self.statusBarTimestamp = statusBarTimestamp
        self.isCurrentFileMissing = document.isCurrentFileMissing
    }
}
