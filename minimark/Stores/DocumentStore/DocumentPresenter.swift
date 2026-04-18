import Foundation

@MainActor
final class DocumentPresenter {
    private let document: DocumentController
    private let sourceEditingController: SourceEditingController
    private let externalChange: ExternalChangeController
    private let toc: TOCController
    private let renderingController: RenderingController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let settler: AutoOpenSettling
    private let fileLoader: MarkdownFileLoader

    init(
        document: DocumentController,
        sourceEditingController: SourceEditingController,
        externalChange: ExternalChangeController,
        toc: TOCController,
        renderingController: RenderingController,
        folderWatchDispatcher: FolderWatchDispatcher,
        settler: AutoOpenSettling,
        fileLoader: MarkdownFileLoader
    ) {
        self.document = document
        self.sourceEditingController = sourceEditingController
        self.externalChange = externalChange
        self.toc = toc
        self.renderingController = renderingController
        self.folderWatchDispatcher = folderWatchDispatcher
        self.settler = settler
        self.fileLoader = fileLoader
    }

    func presentLoaded(
        _ loaded: (markdown: String, modificationDate: Date),
        at fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws {
        renderingController.cancelPendingDraftPreviewRender()
        applyLoadedState(
            loaded,
            presentedAs: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode
        )
        try renderingController.renderImmediately(
            sourceMarkdown: document.sourceMarkdown,
            changedRegions: document.changedRegions,
            unsavedChangedRegions: sourceEditingController.unsavedChangedRegions,
            fileURL: document.fileURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
        if acknowledgeExternalChange {
            externalChange.clear()
        }
        document.isCurrentFileMissing = false
        document.lastError = nil
    }

    func applyLoadedState(
        _ loaded: (markdown: String, modificationDate: Date),
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool
    ) {
        document.fileURL = fileURL
        document.fileDisplayName = fileURL.lastPathComponent
        document.savedMarkdown = loaded.markdown
        sourceEditingController.draftMarkdown = nil
        sourceEditingController.pendingSavedDraftDiffBaselineMarkdown = nil
        document.sourceMarkdown = loaded.markdown
        sourceEditingController.sourceEditorSeedMarkdown = loaded.markdown
        document.fileLastModifiedAt = loaded.modificationDate

        if resetDocumentViewMode {
            sourceEditingController.documentViewMode = .preview
        }

        document.changedRegions = renderingController.computeChangedRegions(
            diffBaselineMarkdown: diffBaselineMarkdown,
            newMarkdown: loaded.markdown
        )
        sourceEditingController.unsavedChangedRegions = []
        sourceEditingController.isSourceEditing = false
        sourceEditingController.hasUnsavedDraftChanges = false
        toc.clear()
    }

    func presentMissing(at fileURL: URL, error: Error) {
        document.fileURL = fileURL
        document.fileDisplayName = fileURL.lastPathComponent
        document.fileLastModifiedAt = nil
        document.openInApplications = []
        document.isCurrentFileMissing = true
        document.lastError = PresentableError(from: error)
        settler.clearSettling()
    }

    func loadAndPresent(
        readURL: URL,
        presentedAs fileURL: URL,
        diffBaselineMarkdown: String?,
        resetDocumentViewMode: Bool,
        acknowledgeExternalChange: Bool
    ) throws -> (markdown: String, modificationDate: Date) {
        let loaded = try fileLoader.load(
            at: readURL,
            folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
        )
        try presentLoaded(
            loaded,
            at: fileURL,
            diffBaselineMarkdown: diffBaselineMarkdown,
            resetDocumentViewMode: resetDocumentViewMode,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
        return loaded
    }
}
