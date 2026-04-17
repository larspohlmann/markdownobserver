import AppKit
import Foundation
import Observation

@MainActor
private struct ReaderWindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void

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

@MainActor
@Observable
final class ReaderWindowCoordinator {
    private let settingsStore: ReaderSettingsStore
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let folderWatchOpenCoordinator = FolderWatchOpenBatcher()
    let openDocumentPathTracker = OpenDocumentPathTracker()

    // Window presentation state
    var hostWindow: NSWindow?
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    let dockTileWindowToken = UUID()
    var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    var lastAppliedSidebarDelta: CGFloat = 0
    var isTitlebarEditingFavorites = false
    var isEditingSubfolders = false
    private var registeredWindowIdentity: RegisteredWindowIdentity?

    private struct RegisteredWindowIdentity: Equatable {
        let windowID: ObjectIdentifier
        let folderWatchSession: ReaderFolderWatchSession?

        init?(window: NSWindow?, folderWatchSession: ReaderFolderWatchSession?) {
            guard let window else { return nil }
            self.windowID = ObjectIdentifier(window)
            self.folderWatchSession = folderWatchSession
        }
    }

    // Controller references (set via configure())
    private(set) var appearanceController: WindowAppearanceController?
    private(set) var groupStateController: SidebarGroupStateController?
    private(set) var favoriteWorkspaceController: FavoriteWorkspaceController?
    private(set) var folderWatchFlowController: FolderWatchFlowController?
    private(set) var uiTestLaunchCoordinator: UITestLaunchCoordinator?
    private(set) var recentHistoryCoordinator: RecentHistoryCoordinator?

    private var fileOpenCoordinator: FileOpenCoordinator {
        sidebarDocumentController.fileOpenCoordinator
    }

    func configure(
        appearanceController: WindowAppearanceController,
        groupStateController: SidebarGroupStateController,
        favoriteWorkspaceController: FavoriteWorkspaceController,
        folderWatchFlowController: FolderWatchFlowController,
        uiTestLaunchCoordinator: UITestLaunchCoordinator,
        recentHistoryCoordinator: RecentHistoryCoordinator
    ) {
        self.appearanceController = appearanceController
        self.groupStateController = groupStateController
        self.favoriteWorkspaceController = favoriteWorkspaceController
        self.folderWatchFlowController = folderWatchFlowController
        self.uiTestLaunchCoordinator = uiTestLaunchCoordinator
        self.recentHistoryCoordinator = recentHistoryCoordinator
        configureStoreCallbacks(
            lockedAppearanceProvider: { [weak appearanceController] in appearanceController?.lockedAppearance }
        ) { [weak self] fileURL, folderWatchSession, origin, initialDiffBaselineMarkdown in
            self?.openAdditionalDocumentInCurrentWindow(
                fileURL,
                folderWatchSession: folderWatchSession,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
            )
        }
    }

    init(
        settingsStore: ReaderSettingsStore,
        sidebarDocumentController: ReaderSidebarDocumentController
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
    }

    var hasPendingFolderWatchOpenEvents: Bool {
        folderWatchOpenCoordinator.hasPendingEvents
    }

    func configureStoreCallbacks(
        lockedAppearanceProvider: @escaping @MainActor () -> LockedAppearance? = { nil },
        onOpenAdditionalDocument: @escaping (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void
    ) {
        sidebarDocumentController.setStoreConfigurator { store in
            ReaderWindowStoreCallbackConfigurator(
                lockedAppearanceProvider: lockedAppearanceProvider,
                onOpenAdditionalDocument: onOpenAdditionalDocument
            ).configure(store)
        }
    }

    private func resolveWindowTitle(activeFolderWatch: ReaderFolderWatchSession?) -> String {
        ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: sidebarDocumentController.selectedWindowTitle,
            activeFolderWatch: activeFolderWatch,
            hasUnacknowledgedExternalChange: sidebarDocumentController.selectedHasUnacknowledgedExternalChange
        )
    }

    private func registerWindow(
        _ hostWindow: NSWindow?,
        activeFolderWatch: ReaderFolderWatchSession?
    ) {
        ReaderWindowRegistry.shared.registerWindow(
            hostWindow,
            focusDocument: { [sidebarDocumentController] fileURL in
                sidebarDocumentController.focusDocument(at: fileURL)
            },
            watchedFolderURLProvider: {
                activeFolderWatch?.folderURL
            }
        )
    }

    // MARK: - Window Shell Flow

    func applyWindowTitlePresentation() {
        let resolvedTitle = resolveWindowTitle(activeFolderWatch: folderWatchFlowController?.sharedFolderWatchSession)
        let mutation = ReaderWindowTitleFormatter.mutation(
            resolvedTitle: resolvedTitle,
            currentEffectiveTitle: effectiveWindowTitle,
            currentHostWindowTitle: hostWindow?.title
        )
        if mutation.shouldUpdateEffectiveTitle {
            effectiveWindowTitle = mutation.effectiveTitle
        }
        if mutation.shouldWriteHostWindowTitle {
            hostWindow?.title = mutation.effectiveTitle
        }
    }

    func enqueueFolderWatchOpen(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin
    ) {
        folderWatchOpenCoordinator.enqueue(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin
        ) { [weak self] in
            self?.flushQueuedFolderWatchOpens()
        }
    }

    func folderWatchChangeEvent(
        for fileURL: URL,
        initialDiffBaselineMarkdown: String?
    ) -> ReaderFolderWatchChangeEvent {
        ReaderFolderWatchChangeEvent(
            fileURL: fileURL,
            kind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            previousMarkdown: initialDiffBaselineMarkdown
        )
    }

    func flushQueuedFolderWatchOpens() {
        let batch = folderWatchOpenCoordinator.consumeBatchIfPossible(
            canFlushImmediately: hostWindow != nil
        ) { [weak self] in
            self?.flushQueuedFolderWatchOpens()
        }

        guard let batch else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: batch.fileURLs,
            origin: batch.openOrigin,
            folderWatchSession: batch.folderWatchSession,
            initialDiffBaselineMarkdownByURL: batch.initialDiffBaselineMarkdownByURL,
            slotStrategy: .reuseEmptySlotForFirst
        ))
        refreshWindowPresentation()
    }

    func openFileRequest(_ request: FileOpenRequest) {
        fileOpenCoordinator.open(request)
        refreshWindowPresentation()
    }

    func refreshSharedFolderWatchState() {
        folderWatchFlowController?.refreshSharedState()
    }

    func refreshWindowPresentation() {
        refreshSharedFolderWatchState()
        applyWindowTitlePresentation()
    }

    func refreshWindowShellRegistrationAndTitle() {
        registerWindowIfNeeded()
        applyWindowTitlePresentation()
    }

    func refreshWindowShellState() {
        refreshSharedFolderWatchState()
        registerWindowIfNeeded()
        applyWindowTitlePresentation()
    }

    func registerWindowIfNeeded() {
        let session = folderWatchFlowController?.sharedFolderWatchSession
        let currentIdentity = RegisteredWindowIdentity(
            window: hostWindow,
            folderWatchSession: session
        )
        guard currentIdentity != registeredWindowIdentity else { return }
        registeredWindowIdentity = currentIdentity
        registerWindow(hostWindow, activeFolderWatch: session)
    }

    func handleFolderWatchToolbarAction(_ action: FolderWatchToolbarAction) {
        switch action {
        case .activate:
            break // Handled by view (requires modal panel)
        case .startFavoriteWatch(let favorite):
            startFavoriteWatch(favorite)
        case .startRecentFolderWatch(let recent):
            recentHistoryCoordinator?.startRecentFolderWatch(recent)
        case .editFavoriteWatchedFolders:
            isTitlebarEditingFavorites = true
        case .clearRecentWatchedFolders:
            recentHistoryCoordinator?.clearRecentWatchedFolders()
        }
    }

    func handleEditFavoritesAction(_ action: EditFavoritesAction) {
        switch action {
        case .rename(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .delete(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorder(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .dismiss:
            isTitlebarEditingFavorites = false
        }
    }

    func handleWindowAccessorUpdate(_ window: NSWindow?) {
        guard hostWindow !== window else { return }
        if let existingWindow = hostWindow {
            ReaderWindowRegistry.shared.unregisterWindow(existingWindow)
            registeredWindowIdentity = nil
        }
        hostWindow = window
        handleHostWindowChange()
    }

    func handleHostWindowChange() {
        refreshWindowShellState()
        uiTestLaunchCoordinator?.applyConfigurationIfNeeded()
        if hostWindow != nil, hasPendingFolderWatchOpenEvents {
            flushQueuedFolderWatchOpens()
        }
    }

    func handleFavoriteWorkspaceStateChange(_ newState: ReaderFavoriteWorkspaceState?) {
        guard let favoriteID = favoriteWorkspaceController?.activeFavoriteID, var state = newState else {
            return
        }
        state.lockedAppearance = appearanceController?.lockedAppearance
        settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
    }

    func handleGroupStateChange(
        oldSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot,
        newSnapshot: SidebarGroupStateController.WorkspaceStateSnapshot
    ) {
        if let favoriteController = favoriteWorkspaceController, favoriteController.isActive {
            let needsUpdate =
                favoriteController.activeFavoriteWorkspaceState?.pinnedGroupIDs != newSnapshot.pinnedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.collapsedGroupIDs != newSnapshot.collapsedGroupIDs ||
                favoriteController.activeFavoriteWorkspaceState?.groupSortMode != newSnapshot.sortMode ||
                favoriteController.activeFavoriteWorkspaceState?.fileSortMode != newSnapshot.fileSortMode ||
                favoriteController.activeFavoriteWorkspaceState?.manualGroupOrder != newSnapshot.manualGroupOrder

            if needsUpdate {
                favoriteController.updateGroupState(
                    pinnedGroupIDs: newSnapshot.pinnedGroupIDs,
                    collapsedGroupIDs: newSnapshot.collapsedGroupIDs,
                    groupSortMode: newSnapshot.sortMode,
                    fileSortMode: newSnapshot.fileSortMode,
                    manualGroupOrder: newSnapshot.manualGroupOrder
                )
            }
        } else {
            if oldSnapshot.sortMode != newSnapshot.sortMode {
                settingsStore.updateSidebarGroupSortMode(newSnapshot.sortMode)
            }
            if oldSnapshot.fileSortMode != newSnapshot.fileSortMode {
                settingsStore.updateSidebarSortMode(newSnapshot.fileSortMode)
            }
        }
    }

    func handleDocumentListChange() {
        groupStateController?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
    }

    func handleWindowAppear() {
        groupStateController?.configureSortModes(
            sortMode: settingsStore.currentSettings.sidebarGroupSortMode,
            fileSortMode: settingsStore.currentSettings.sidebarSortMode
        )
        groupStateController?.updateDocuments(
            sidebarDocumentController.documents,
            rowStates: sidebarDocumentController.rowStates
        )
        groupStateController?.observeRowStates(from: sidebarDocumentController)
        openDocumentPathTracker.update(from: sidebarDocumentController.documents)
        DockTileController.shared.configureDockTileIfNeeded()
        let token = dockTileWindowToken
        sidebarDocumentController.onDockTileRowStatesChanged = { rowStates in
            DockTileController.shared.updateRowStates(for: token, rowStates: rowStates)
        }
        DockTileController.shared.updateRowStates(
            for: token,
            rowStates: sidebarDocumentController.rowStates
        )
    }

    func handleWindowDisappear() {
        sidebarDocumentController.onDockTileRowStatesChanged = nil
        DockTileController.shared.removeRowStates(for: dockTileWindowToken)
    }

    func handleSidebarWidthChange(_ newWidth: CGFloat) {
        sidebarWidth = newWidth
        if favoriteWorkspaceController?.activeFavoriteWorkspaceState != nil,
           sidebarDocumentController.documents.count > 1 {
            favoriteWorkspaceController?.updateSidebarWidth(newWidth)
        }
    }

    func handleSidebarVisibilityChange(oldCount: Int, newCount: Int) {
        let isSidebarVisible = newCount > 1
        let wasVisible = oldCount > 1

        guard isSidebarVisible != wasVisible, let window = hostWindow else {
            return
        }

        if isSidebarVisible, let favoriteWidth = favoriteWorkspaceController?.activeFavoriteWorkspaceState?.sidebarWidth {
            sidebarWidth = favoriteWidth
        }

        let delta = isSidebarVisible
            ? sidebarWidth
            : -lastAppliedSidebarDelta

        guard let screenFrame = window.screen?.visibleFrame else {
            return
        }

        let oldWidth = window.frame.width
        let newFrame = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: window.frame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: delta
        )

        window.setFrame(newFrame, display: true, animate: true)

        if isSidebarVisible {
            lastAppliedSidebarDelta = newFrame.width - oldWidth
        } else {
            lastAppliedSidebarDelta = 0
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
    }

    // MARK: - Open and Watch Flow

    func openIncomingURL(_ url: URL) {
        guard ReaderWindowOpenAndWatchFlowSupport.isSupportedIncomingMarkdownFile(url) else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [url],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))
        applyWindowTitlePresentation()
    }

    func openDocumentInCurrentWindow(_ fileURL: URL) {
        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [fileURL],
            origin: .manual,
            folderWatchSession: folderWatchFlowController?.sharedFolderWatchSession,
            slotStrategy: .replaceSelectedSlot
        ))
        applyWindowTitlePresentation()
    }

    func applyInitialSeedIfNeeded(seed: ReaderWindowSeed?) {
        ReaderWindowOpenAndWatchFlowSupport.applyInitialSeedIfNeeded(
            seed: seed,
            openDocumentInCurrentWindow: { fileURL in
                openDocumentInCurrentWindow(fileURL)
            },
            openDocumentInSelectedSlot: { fileURL, origin, folderWatchSession, initialDiffBaselineMarkdown in
                openDocumentInSelectedSlot(
                    at: fileURL,
                    origin: origin,
                    folderWatchSession: folderWatchSession,
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                )
            },
            resolveRecentOpenedFileURL: { entry in
                settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
            },
            resolveRecentWatchedFolderURL: { entry in
                settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
            },
            prepareRecentFolderWatch: { [weak self] folderURL, options in
                self?.folderWatchFlowController?.presentOptions(for: folderURL, options: options)
            }
        )
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
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
        applyWindowTitlePresentation()
    }

    // Folder watch presentation and options are managed directly by FolderWatchFlowController.

    // MARK: - Sidebar Command Flow

    func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: ReaderFolderWatchSession? = nil,
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
        folderWatchSession: ReaderFolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)

        if folderWatchSession != nil {
            enqueueFolderWatchOpen(
                folderWatchChangeEvent(
                    for: normalizedFileURL,
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                ),
                folderWatchSession: folderWatchSession,
                origin: origin
            )
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: [normalizedFileURL],
            origin: origin,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdown.map { [normalizedFileURL: $0] } ?? [:],
            slotStrategy: .reuseEmptySlotForFirst
        ))
        applyWindowTitlePresentation()
    }

    var isSharedFolderWatchAFavorite: Bool {
        favoriteWorkspaceController?.isCurrentWatchAFavorite ?? false
    }

    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
        guard let favoriteWorkspaceController else { return }
        let restoredSidebarWidth = favoriteWorkspaceController.startFavoriteWatch(entry)
        sidebarWidth = restoredSidebarWidth
        refreshWindowPresentation()
    }

    func startWatchingFolder(
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) {
        let deactivated = folderWatchFlowController?.startWatchingFolder(
            folderURL: folderURL,
            options: options,
            performInitialAutoOpen: performInitialAutoOpen
        ) ?? false
        if deactivated {
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
        refreshWindowPresentation()
    }

    func performSidebarMutation(_ mutation: () -> Void) {
        mutation()
        refreshWindowPresentation()
    }

    func closeSidebarDocument(_ documentID: UUID) {
        performSidebarMutation {
            sidebarDocumentController.closeDocument(documentID)
        }
    }

    func openSidebarDocumentsInDefaultApp(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(nil, documentIDs: documentIDs)
    }

    func openSidebarDocumentsInApplication(_ application: ReaderExternalApplication, _ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(application, documentIDs: documentIDs)
    }

    func revealSidebarDocumentsInFinder(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.revealDocumentsInFinder(documentIDs)
    }

    func stopWatchingSidebarFolders(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.folderWatchCoordinator.stopWatchingFolders(documentIDs)
        }
    }

    func closeOtherSidebarDocuments(keeping documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeOtherDocuments(keeping: documentIDs)
        }
    }

    func closeSelectedSidebarDocuments(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeDocuments(documentIDs)
        }
    }

    func closeAllSidebarDocuments() {
        performSidebarMutation {
            sidebarDocumentController.closeAllDocuments()
        }
    }

    func toggleSidebarPlacement(currentMultiFileDisplayMode: ReaderMultiFileDisplayMode) {
        if let current = favoriteWorkspaceController?.activeFavoriteWorkspaceState?.sidebarPosition {
            favoriteWorkspaceController?.updateSidebarPosition(current.toggledSidebarPlacementMode)
            favoriteWorkspaceController?.updateSidebarWidth(sidebarWidth)
        } else {
            settingsStore.updateMultiFileDisplayMode(currentMultiFileDisplayMode.toggledSidebarPlacementMode)
        }
    }

    @discardableResult
    func updateFolderWatchExclusions(_ newExcludedPaths: [String]) -> Bool {
        let result = folderWatchFlowController?.updateFolderWatchExclusions(newExcludedPaths) ?? false
        refreshWindowPresentation()
        return result
    }

    // MARK: - Warning Flow

    func confirmFolderWatch(_ options: ReaderFolderWatchOptions) {
        let deactivated = folderWatchFlowController?.confirmFolderWatch(options) ?? false
        if deactivated {
            sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
        refreshWindowPresentation()
    }

    func stopFolderWatch() {
        folderWatchFlowController?.stopFolderWatchSession()
        sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        refreshWindowPresentation()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: FolderWatchAutoOpenWarning?) {
        folderWatchFlowController?.handleAutoOpenWarningChangeForWindow(warning, hostWindow: hostWindow)
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        folderWatchFlowController?.refreshAutoOpenWarningPresentationForWindow(hostWindow: hostWindow)
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        folderWatchFlowController?.openSelectedAutoOpenFilesAndRefresh()
        refreshWindowPresentation()
    }

    // MARK: - Action Dispatch

    func handleContentViewAction(_ action: ContentViewAction) {
        switch action {
        case .requestFileOpen(let request):
            fileOpenCoordinator.open(request)
            refreshWindowPresentation()
        case .requestFolderWatch(let url):
            folderWatchFlowController?.prepareOptions(for: url)
        case .confirmFolderWatch(let options):
            confirmFolderWatch(options)
        case .cancelFolderWatch:
            folderWatchFlowController?.cancelPendingWatch()
        case .stopFolderWatch:
            stopFolderWatch()
        case .saveFolderWatchAsFavorite(let name):
            favoriteWorkspaceController?.saveAsFavorite(name: name, currentSidebarWidth: sidebarWidth)
        case .removeCurrentWatchFromFavorites:
            favoriteWorkspaceController?.removeFromFavorites()
        case .toggleAppearanceLock:
            toggleAppearanceLock()
        case .startFavoriteWatch(let fav):
            startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders:
            favoriteWorkspaceController?.clearAll()
        case .renameFavoriteWatchedFolder(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .removeFavoriteWatchedFolder(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorderFavoriteWatchedFolders(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .startRecentManuallyOpenedFile(let entry):
            recentHistoryCoordinator?.openRecentFile(entry, using: fileOpenCoordinator, session: folderWatchFlowController?.sharedFolderWatchSession)
            applyWindowTitlePresentation()
        case .startRecentFolderWatch(let entry):
            recentHistoryCoordinator?.startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders:
            recentHistoryCoordinator?.clearRecentWatchedFolders()
        case .clearRecentManuallyOpenedFiles:
            recentHistoryCoordinator?.clearRecentManuallyOpenedFiles()
        case .editSubfolders:
            isEditingSubfolders = true
        case .saveSourceDraft:
            sidebarDocumentController.selectedReaderStore.saveSourceDraft()
        case .discardSourceDraft:
            sidebarDocumentController.selectedReaderStore.discardSourceDraft()
        case .startSourceEditing:
            sidebarDocumentController.selectedReaderStore.startEditingSource()
        case .updateSourceDraft(let markdown):
            sidebarDocumentController.selectedReaderStore.updateSourceDraft(markdown)
        case .grantImageDirectoryAccess(let url):
            sidebarDocumentController.selectedReaderStore.grantImageDirectoryAccess(folderURL: url)
        case .openInApplication(let app):
            sidebarDocumentController.selectedReaderStore.document.openInApplication(app)
        case .revealInFinder:
            sidebarDocumentController.selectedReaderStore.document.revealInFinder()
        case .presentError(let error):
            sidebarDocumentController.selectedReaderStore.handle(error)
        case .updateTOCHeadings(let headings):
            sidebarDocumentController.selectedReaderStore.toc.updateHeadings(headings)
        }
    }

    // MARK: - Appearance Lock

    func toggleAppearanceLock() {
        guard let appearanceController else { return }
        if appearanceController.isLocked {
            appearanceController.unlock()
            for document in sidebarDocumentController.documents {
                document.readerStore.renderingController.clearAppearanceOverride()
            }
            if favoriteWorkspaceController?.activeFavoriteWorkspaceState != nil {
                favoriteWorkspaceController?.updateLockedAppearance(nil)
            }
        } else {
            appearanceController.lock()
            let appearance = appearanceController.effectiveAppearance
            for document in sidebarDocumentController.documents {
                document.readerStore.renderingController.setAppearanceOverride(appearance)
            }
            if favoriteWorkspaceController?.activeFavoriteWorkspaceState != nil {
                favoriteWorkspaceController?.updateLockedAppearance(appearanceController.lockedAppearance)
            }
        }
    }

    // MARK: - Appearance Reapplication

    func reapplyAppearance() {
        guard let appearanceController else { return }
        // Defer rendering to the next main actor hop to avoid setting @Published
        // properties on ReaderStore during a SwiftUI view update cycle.
        Task { @MainActor [sidebarDocumentController] in
            let appearance = appearanceController.effectiveAppearance
            for document in sidebarDocumentController.documents {
                let store = document.readerStore
                guard store.document.hasOpenDocument, !store.document.isDeferredDocument else { continue }

                if document.id == sidebarDocumentController.selectedDocumentID {
                    try? store.renderWithAppearance(appearance)
                } else {
                    store.setAppearanceOverride(appearance)
                }
            }
        }
    }

    func renderSelectedDocumentIfNeeded() {
        guard let appearanceController else { return }
        guard let document = sidebarDocumentController.selectedDocument else { return }
        let store = document.readerStore
        guard store.renderingController.needsAppearanceRender, store.document.hasOpenDocument, !store.document.isDeferredDocument else { return }
        Task { @MainActor in
            try? store.renderWithAppearance(appearanceController.effectiveAppearance)
        }
    }
}
