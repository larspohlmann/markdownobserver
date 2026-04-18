import Foundation

@MainActor
final class DocumentReloader {
    private let document: DocumentController
    private let folderWatch: FolderWatchDependencies
    private let presenter: DocumentPresenter
    private let onError: @MainActor (Error) -> Void

    init(
        document: DocumentController,
        folderWatch: FolderWatchDependencies,
        presenter: DocumentPresenter,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.document = document
        self.folderWatch = folderWatch
        self.presenter = presenter
        self.onError = onError
    }

    func reloadCurrentFile(
        forceHighlight: Bool = true,
        acknowledgeExternalChange: Bool = true
    ) {
        guard let fileURL = document.fileURL else {
            return
        }

        reload(
            at: fileURL,
            diffBaselineMarkdown: forceHighlight ? document.sourceMarkdown : nil,
            acknowledgeExternalChange: acknowledgeExternalChange
        )
    }

    func reload(
        at fileURL: URL?,
        diffBaselineMarkdown: String?,
        acknowledgeExternalChange: Bool
    ) {
        guard let fileURL else {
            return
        }

        do {
            _ = try presenter.loadAndPresent(
                readURL: fileURL,
                presentedAs: fileURL,
                diffBaselineMarkdown: diffBaselineMarkdown,
                resetDocumentViewMode: false,
                acknowledgeExternalChange: acknowledgeExternalChange
            )
            folderWatch.settler.clearSettling()
        } catch {
            handleReloadFailure(error, for: fileURL)
        }
    }

    func handleReloadFailure(_ error: Error, for fileURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            onError(error)
            return
        }

        presenter.presentMissing(at: fileURL, error: error)
    }
}
