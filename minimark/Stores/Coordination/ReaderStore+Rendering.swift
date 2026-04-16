import Foundation

extension ReaderStore {
    func scheduleDraftPreviewRender() {
        renderingController.scheduleDraftPreviewRender(
            sourceMarkdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            fileURL: fileURL,
            folderWatchSession: activeFolderWatchSession
        )
    }

    func cancelPendingDraftPreviewRender() {
        renderingController.cancelPendingDraftPreviewRender()
    }

    func renderCurrentMarkdownImmediately() throws {
        try renderingController.renderImmediately(
            sourceMarkdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            fileURL: fileURL,
            folderWatchSession: activeFolderWatchSession
        )
    }

    func renderWithAppearance(_ appearance: LockedAppearance) throws {
        try renderingController.renderWithAppearance(
            appearance,
            sourceMarkdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            fileURL: fileURL,
            folderWatchSession: activeFolderWatchSession
        )
    }

    func setAppearanceOverride(_ appearance: LockedAppearance) {
        renderingController.setAppearanceOverride(appearance)
    }

    func clearAppearanceOverride() {
        renderingController.clearAppearanceOverride()
    }

}
