import Foundation

/// Applies a user's baseline pick: updates the selection controller, recomputes
/// the changed regions of the current document, and re-renders the preview.
/// Does not read the file from disk.
@MainActor
final class DiffBaselineRecomparer {
    private let document: DocumentController
    private let sourceEditingController: SourceEditingController
    private let renderingController: RenderingController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let diffBaselineSelection: DiffBaselineSelectionController
    private let onError: @MainActor (Error) -> Void

    init(
        document: DocumentController,
        sourceEditingController: SourceEditingController,
        renderingController: RenderingController,
        folderWatchDispatcher: FolderWatchDispatcher,
        diffBaselineSelection: DiffBaselineSelectionController,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.document = document
        self.sourceEditingController = sourceEditingController
        self.renderingController = renderingController
        self.folderWatchDispatcher = folderWatchDispatcher
        self.diffBaselineSelection = diffBaselineSelection
        self.onError = onError
    }

    func apply(_ selection: DiffBaselineSelection, at now: Date = .now) {
        guard let fileURL = document.fileURL,
              !sourceEditingController.isSourceEditing else {
            return
        }

        let baseline: DiffBaselineSnapshot?
        switch selection {
        case .automatic:
            baseline = diffBaselineSelection.selectAutomatic(for: fileURL, at: now)
        case .snapshot(let id):
            guard let pinned = diffBaselineSelection.pin(id, for: fileURL) else {
                return
            }
            baseline = pinned
        }

        document.changedRegions = renderingController.computeChangedRegions(
            diffBaselineMarkdown: baseline?.markdown,
            newMarkdown: document.sourceMarkdown
        )

        do {
            try renderingController.renderImmediately(
                sourceMarkdown: document.sourceMarkdown,
                changedRegions: document.changedRegions,
                unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
                fileURL: document.fileURL,
                folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
        } catch {
            onError(error)
        }
    }
}
