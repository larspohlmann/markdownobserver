import Foundation

/// Configures a newly-created `DocumentStore` with the window's locked appearance
/// and an additional-open handler. Invoked by the sidebar document controller
/// each time it instantiates a store for a new slot.
@MainActor
private struct WindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, FolderWatchSession?, OpenOrigin, String?) -> Void

    func configure(_ store: DocumentStore) {
        if let lockedAppearance = lockedAppearanceProvider() {
            store.renderingController.setAppearanceOverride(lockedAppearance)
        }
        store.folderWatchDispatcher.setAdditionalOpenHandler { event, folderWatchSession, origin in
            onOpenAdditionalDocument(
                event.fileURL,
                folderWatchSession,
                origin,
                event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }
}

/// Owns the window-level document open flows: incoming URLs, seed application,
/// current-window / selected-slot / additional-document opens, and the wiring
/// that configures newly-created `DocumentStore`s with the window's locked
/// appearance plus an additional-open handler.
///
/// Does not own the folder-watch open queue (see `WindowFolderWatchOpenController`) —
/// only dispatches to it when an additional open carries a live folder-watch
/// session.
@MainActor
final class WindowDocumentOpenCoordinator {
    private let fileOpenCoordinator: FileOpenCoordinator
    private let folderWatchOpen: WindowFolderWatchOpenController
    private let sidebarDocumentController: SidebarDocumentController
    private let settingsStore: SettingsStore
    private let linkFollowAccessRequester: LinkFollowAccessRequester
    private let folderWatchSessionProvider: () -> FolderWatchSession?
    private let callbacks: WindowOpenCallbacks

    init(
        fileOpenCoordinator: FileOpenCoordinator,
        folderWatchOpen: WindowFolderWatchOpenController,
        sidebarDocumentController: SidebarDocumentController,
        settingsStore: SettingsStore,
        linkFollowAccessRequester: LinkFollowAccessRequester? = nil,
        folderWatchSessionProvider: @escaping () -> FolderWatchSession?,
        callbacks: WindowOpenCallbacks
    ) {
        self.fileOpenCoordinator = fileOpenCoordinator
        self.folderWatchOpen = folderWatchOpen
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.linkFollowAccessRequester = linkFollowAccessRequester
            ?? LinkFollowAccessRequester(grantStore: settingsStore)
        self.folderWatchSessionProvider = folderWatchSessionProvider
        self.callbacks = callbacks
    }

    /// Install the store-callback configurator on the sidebar document controller.
    /// Must be called after the appearance controller is available.
    func configureStoreCallbacks(
        lockedAppearanceProvider: @escaping @MainActor () -> LockedAppearance? = { nil }
    ) {
        sidebarDocumentController.setStoreConfigurator { [weak self] store in
            WindowStoreCallbackConfigurator(
                lockedAppearanceProvider: lockedAppearanceProvider,
                onOpenAdditionalDocument: { fileURL, folderWatchSession, origin, initialDiffBaselineMarkdown in
                    self?.openAdditionalDocumentInCurrentWindow(
                        fileURL,
                        folderWatchSession: folderWatchSession,
                        origin: origin,
                        initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                    )
                }
            ).configure(store)
        }
    }

    // MARK: - Open entry points

    func openFileRequest(_ request: FileOpenRequest) {
        if request.origin == .linkFollow {
            guard ensureLinkFollowAccess(forFiles: request.fileURLs) else { return }
        }
        fileOpenCoordinator.open(request)
        callbacks.refreshWindowPresentation()
    }

    /// Sandboxed apps only have access to files the user explicitly grants.
    /// When following a markdown link to a sibling/descendant file, that file
    /// usually isn't accessible until the user grants the parent folder. We
    /// detect that here and present an NSOpenPanel to collect the grant —
    /// which is then persisted so future link clicks under the same folder
    /// don't re-prompt.
    ///
    /// Returns `true` when access is already covered or was successfully
    /// granted. Returns `false` when the user cancelled or chose a folder
    /// that doesn't cover the target — callers must abort the file open in
    /// that case to avoid a broken slot showing a sandbox read failure.
    ///
    /// Link-follow file opens always carry exactly one URL (see
    /// `DocumentSurfaceViewModel.openLinkedFile(_:)`).
    private func ensureLinkFollowAccess(forFiles fileURLs: [URL]) -> Bool {
        precondition(fileURLs.count == 1, "link-follow open expects exactly one file URL")
        guard let firstFileURL = fileURLs.first else { return false }
        if settingsStore.resolvedLinkAccessFolderURL(containing: firstFileURL) != nil {
            return true
        }
        return linkFollowAccessRequester.requestAccess(forContaining: firstFileURL)
    }

    func openIncomingURL(_ url: URL) {
        guard WindowOpenAndWatchFlowSupport.isSupportedIncomingMarkdownFile(url) else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [url],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))
        callbacks.applyTitlePresentation()
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [fileURL],
            origin: .manual,
            folderWatchSession: folderWatchSessionProvider(),
            slotStrategy: .replaceSelectedSlot
        ))
        callbacks.applyTitlePresentation()
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: OpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedURL = FileRouting.normalizedFileURL(fileURL)
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedURL],
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedURL: $0] } ?? [:],
            slotStrategy: .replaceSelectedSlot
        ))
        callbacks.applyTitlePresentation()
    }

    func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: FolderWatchSession? = nil,
        origin: OpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)

        if WindowRegistry.shared.focusDocumentIfAlreadyOpen(at: normalizedFileURL) {
            return
        }

        openAdditionalDocumentInCurrentWindow(
            fileURL,
            folderWatchSession: folderWatchSession,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
    }

    func openAdditionalDocumentInCurrentWindow(
        _ fileURL: URL,
        folderWatchSession: FolderWatchSession? = nil,
        origin: OpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = FileRouting.normalizedFileURL(fileURL)

        if folderWatchSession != nil {
            let event = FolderWatchChangeEvent(
                fileURL: normalizedFileURL,
                kind: initialDiffBaselineMarkdown == nil ? .added : .modified,
                previousMarkdown: initialDiffBaselineMarkdown
            )
            folderWatchOpen.enqueue(event, folderWatchSession: folderWatchSession, origin: origin)
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedFileURL],
            origin: origin,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedFileURL: $0] } ?? [:],
            slotStrategy: .reuseEmptySlotForFirst
        ))
        callbacks.applyTitlePresentation()
    }

    func applyInitialSeedIfNeeded(seed: WindowSeed?) {
        WindowOpenAndWatchFlowSupport.applyInitialSeedIfNeeded(
            seed: seed,
            openDocumentInCurrentWindow: { [weak self] fileURL in
                self?.openDocumentInCurrentWindow(fileURL)
            },
            openDocumentInSelectedSlot: { [weak self] fileURL, origin, folderWatchSession, initialDiffBaselineMarkdown in
                self?.openDocumentInSelectedSlot(
                    at: fileURL,
                    origin: origin,
                    folderWatchSession: folderWatchSession,
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                )
            },
            resolveRecentOpenedFileURL: { [settingsStore] entry in
                settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
            },
            resolveRecentWatchedFolderURL: { [settingsStore] entry in
                settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
            },
            prepareRecentFolderWatch: { [weak self] folderURL, options in
                self?.callbacks.prepareRecentFolderWatch(folderURL, options)
            }
        )
    }
}
