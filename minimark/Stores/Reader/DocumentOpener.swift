import Foundation

@MainActor
final class DocumentOpener {
    private let document: ReaderDocumentController
    private let externalChange: ReaderExternalChangeController
    private let sourceEditingController: ReaderSourceEditingController
    private let folderWatchDispatcher: FolderWatchDispatcher
    private let securityScopeResolver: SecurityScopeResolver
    private let folderWatch: FolderWatchDependencies
    private let fileWatcher: FileChangeWatching
    private let fileLoader: MarkdownFileLoader
    private let presenter: DocumentPresenter
    private let postOpenEffects: PostOpenEffects
    var onActivateDeferredSetupIfNeeded: (@MainActor () -> Void)?
    private let onError: @MainActor (Error) -> Void

    init(
        document: ReaderDocumentController,
        externalChange: ReaderExternalChangeController,
        sourceEditingController: ReaderSourceEditingController,
        folderWatchDispatcher: FolderWatchDispatcher,
        securityScopeResolver: SecurityScopeResolver,
        folderWatch: FolderWatchDependencies,
        fileWatcher: FileChangeWatching,
        fileLoader: MarkdownFileLoader,
        presenter: DocumentPresenter,
        postOpenEffects: PostOpenEffects,
        onError: @escaping @MainActor (Error) -> Void
    ) {
        self.document = document
        self.externalChange = externalChange
        self.sourceEditingController = sourceEditingController
        self.folderWatchDispatcher = folderWatchDispatcher
        self.securityScopeResolver = securityScopeResolver
        self.folderWatch = folderWatch
        self.fileWatcher = fileWatcher
        self.fileLoader = fileLoader
        self.presenter = presenter
        self.postOpenEffects = postOpenEffects
        self.onError = onError
    }

    func open(at url: URL) {
        open(at: url, origin: .manual)
    }

    func open(
        at url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        onActivateDeferredSetupIfNeeded?()
        do {
            let accessibleURL = url
            let normalizedURL = ReaderFileRouting.normalizedFileURL(accessibleURL)
            securityScopeResolver.activateFileSecurityScope(for: accessibleURL, reason: "open")
            if let folderWatchSession {
                folderWatchDispatcher.setSession(securityScopeResolver.normalizedFolderWatchSession(folderWatchSession))
            }
            let readURL = securityScopeResolver.effectiveAccessibleFileURL(
                for: normalizedURL, reason: "open", folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )
            document.currentOpenOrigin = origin

            let loaded = try fileLoader.load(
                at: readURL,
                folderWatchSession: folderWatchDispatcher.activeFolderWatchSession
            )

            // Stop previous file-watch callbacks before mutating the active
            // document identity so stale events cannot cross into the new file state.
            fileWatcher.stopWatching()

            try presenter.presentLoaded(
                loaded,
                at: normalizedURL,
                diffBaselineMarkdown: initialDiffBaselineMarkdown,
                resetDocumentViewMode: true,
                acknowledgeExternalChange: true
            )

            postOpenEffects.apply(
                accessibleURL: accessibleURL,
                normalizedURL: normalizedURL,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loaded.markdown
            )
        } catch {
            onError(error)
        }
    }

    func materializeDeferred(
        origin: ReaderOpenOrigin? = nil,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard document.documentLoadState == .deferred || document.documentLoadState == .loading,
              let url = document.fileURL else {
            return
        }

        if document.documentLoadState == .deferred {
            document.transitionToLoading()
        }

        open(
            at: url,
            origin: origin ?? document.currentOpenOrigin,
            folderWatchSession: folderWatchSession ?? folderWatchDispatcher.activeFolderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )

        // Safety: if openFile failed internally, clear the loading state
        document.clearLoadingState()

        if initialDiffBaselineMarkdown != nil {
            externalChange.noteObservedExternalChange(kind: .modified)
        }
    }

    func handleIncomingURL(_ url: URL) {
        handleIncomingURL(url, origin: .manual)
    }

    func handleIncomingURL(
        _ url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard url.isFileURL else {
            return
        }

        guard ReaderFileRouting.isSupportedMarkdownFileURL(url) else {
            return
        }

        let normalizedIncomingURL = ReaderFileRouting.normalizedFileURL(url)
        if let fileURL = document.fileURL, ReaderFileRouting.normalizedFileURL(fileURL) == normalizedIncomingURL {
            return
        }

        open(
            at: normalizedIncomingURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    func deferFile(
        at url: URL,
        origin: ReaderOpenOrigin = .folderWatchInitialBatchAutoOpen,
        folderWatchSession: FolderWatchSession?
    ) {
        document.deferFile(at: url, origin: origin)
        if let folderWatchSession {
            folderWatchDispatcher.setSession(folderWatchSession)
        }
    }

    /// Marks this document as live-auto-opened: sets the external change
    /// indicator and clears the settler so subsequent edits are not absorbed.
    func markAsLiveAutoOpened() {
        externalChange.noteObservedExternalChange(kind: .added)
        folderWatch.settler.clearSettling()
    }
}
