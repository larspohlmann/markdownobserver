import Foundation

/// Configures a newly-created `ReaderStore` with the window's locked appearance
/// and an additional-open handler. Invoked by the sidebar document controller
/// each time it instantiates a store for a new slot.
@MainActor
private struct WindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, FolderWatchSession?, ReaderOpenOrigin, String?) -> Void

    func configure(_ store: ReaderStore) {
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
/// that configures newly-created `ReaderStore`s with the window's locked
/// appearance plus an additional-open handler.
///
/// Does not own the folder-watch open queue (see `WindowFolderWatchOpenController`) —
/// only dispatches to it when an additional open carries a live folder-watch
/// session.
@MainActor
final class WindowDocumentOpenCoordinator {
    private let fileOpenCoordinator: FileOpenCoordinator
    private let folderWatchOpenController: WindowFolderWatchOpenController
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let settingsStore: ReaderSettingsStore
    private let folderWatchSessionProvider: () -> FolderWatchSession?
    private let applyTitlePresentation: () -> Void
    private let refreshWindowPresentation: () -> Void
    private let prepareRecentFolderWatch: (URL, FolderWatchOptions) -> Void

    init(
        fileOpenCoordinator: FileOpenCoordinator,
        folderWatchOpenController: WindowFolderWatchOpenController,
        sidebarDocumentController: ReaderSidebarDocumentController,
        settingsStore: ReaderSettingsStore,
        folderWatchSessionProvider: @escaping () -> FolderWatchSession?,
        applyTitlePresentation: @escaping () -> Void,
        refreshWindowPresentation: @escaping () -> Void,
        prepareRecentFolderWatch: @escaping (URL, FolderWatchOptions) -> Void
    ) {
        self.fileOpenCoordinator = fileOpenCoordinator
        self.folderWatchOpenController = folderWatchOpenController
        self.sidebarDocumentController = sidebarDocumentController
        self.settingsStore = settingsStore
        self.folderWatchSessionProvider = folderWatchSessionProvider
        self.applyTitlePresentation = applyTitlePresentation
        self.refreshWindowPresentation = refreshWindowPresentation
        self.prepareRecentFolderWatch = prepareRecentFolderWatch
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
        fileOpenCoordinator.open(request)
        refreshWindowPresentation()
    }

    func openIncomingURL(_ url: URL) {
        guard ReaderWindowOpenAndWatchFlowSupport.isSupportedIncomingMarkdownFile(url) else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [url],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))
        applyTitlePresentation()
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [fileURL],
            origin: .manual,
            folderWatchSession: folderWatchSessionProvider(),
            slotStrategy: .replaceSelectedSlot
        ))
        applyTitlePresentation()
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: FolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedURL],
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedURL: $0] } ?? [:],
            slotStrategy: .replaceSelectedSlot
        ))
        applyTitlePresentation()
    }

    func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: FolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)

        if ReaderWindowRegistry.shared.focusDocumentIfAlreadyOpen(at: normalizedFileURL) {
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
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)

        if folderWatchSession != nil {
            let event = FolderWatchChangeEvent(
                fileURL: normalizedFileURL,
                kind: initialDiffBaselineMarkdown == nil ? .added : .modified,
                previousMarkdown: initialDiffBaselineMarkdown
            )
            folderWatchOpenController.enqueue(event, folderWatchSession: folderWatchSession, origin: origin)
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedFileURL],
            origin: origin,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedFileURL: $0] } ?? [:],
            slotStrategy: .reuseEmptySlotForFirst
        ))
        applyTitlePresentation()
    }

    func applyInitialSeedIfNeeded(seed: ReaderWindowSeed?) {
        ReaderWindowOpenAndWatchFlowSupport.applyInitialSeedIfNeeded(
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
                self?.prepareRecentFolderWatch(folderURL, options)
            }
        )
    }
}
