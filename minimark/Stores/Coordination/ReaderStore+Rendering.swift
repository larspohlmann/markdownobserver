import Foundation

extension ReaderStore {
    func scheduleDraftPreviewRender() {
        renderingController.scheduleDraftPreviewRender(
            sourceMarkdown: document.sourceMarkdown,
            changedRegions: document.changedRegions,
            unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
            fileURL: document.fileURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
    }

    func cancelPendingDraftPreviewRender() {
        renderingController.cancelPendingDraftPreviewRender()
    }

    func renderCurrentMarkdownImmediately() throws {
        try renderingController.renderImmediately(
            sourceMarkdown: document.sourceMarkdown,
            changedRegions: document.changedRegions,
            unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
            fileURL: document.fileURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
    }

    func renderWithAppearance(_ appearance: LockedAppearance) throws {
        try renderingController.renderWithAppearance(
            appearance,
            sourceMarkdown: document.sourceMarkdown,
            changedRegions: document.changedRegions,
            unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
            fileURL: document.fileURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
    }

    func setAppearanceOverride(_ appearance: LockedAppearance) {
        renderingController.setAppearanceOverride(appearance)
    }

    func clearAppearanceOverride() {
        renderingController.clearAppearanceOverride()
    }

}
