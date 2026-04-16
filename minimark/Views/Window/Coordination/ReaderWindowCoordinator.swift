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
    private let folderWatchOpenCoordinator = ReaderFolderWatchOpenCoordinator()
    let openDocumentPathTracker = OpenDocumentPathTracker()

    // Window presentation state
    var hostWindow: NSWindow?
    var hasCompletedWindowPhase = false
    var hasOpenedInitialFile = false
    var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    let dockTileWindowToken = UUID()
    var hasAppliedUITestLaunchConfiguration = false
    var uiTestWatchFlowTask: Task<Void, Never>?
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

    private var fileOpenCoordinator: FileOpenCoordinator {
        sidebarDocumentController.fileOpenCoordinator
    }

    func configure(
        appearanceController: WindowAppearanceController,
        groupStateController: SidebarGroupStateController,
        favoriteWorkspaceController: FavoriteWorkspaceController,
        folderWatchFlowController: FolderWatchFlowController
    ) {
        self.appearanceController = appearanceController
        self.groupStateController = groupStateController
        self.favoriteWorkspaceController = favoriteWorkspaceController
        self.folderWatchFlowController = folderWatchFlowController
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
            startRecentFolderWatch(recent)
        case .editFavoriteWatchedFolders:
            isTitlebarEditingFavorites = true
        case .clearRecentWatchedFolders:
            clearRecentWatchedFolders()
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

    func handleOpenRecentFileNotification(_ notification: Notification) {
        guard let payload = ReaderCommandNotification.Payload(notification: notification),
              payload.targetWindowNumber == hostWindow?.windowNumber else {
            return
        }

        guard let entry = payload.recentFileEntry else {
            return
        }

        let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
        openDocumentInCurrentWindow(resolvedURL)
    }

    func handlePrepareRecentWatchedFolderNotification(_ notification: Notification) {
        guard let payload = ReaderCommandNotification.Payload(notification: notification),
              payload.targetWindowNumber == hostWindow?.windowNumber else {
            return
        }

        guard let entry = payload.recentWatchedFolderEntry else {
            return
        }

        prepareRecentFolderWatch(entry)
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
        applyUITestLaunchConfigurationIfNeeded()
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
            prepareRecentFolderWatch: { folderURL, options in
                presentFolderWatchOptions(for: folderURL, options: options)
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

    func prepareFolderWatchOptions(for folderURL: URL) {
        folderWatchFlowController?.prepareOptions(for: folderURL)
    }

    func presentFolderWatchOptions(for folderURL: URL, options: ReaderFolderWatchOptions) {
        folderWatchFlowController?.presentOptions(for: folderURL, options: options)
    }

    func prepareRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        folderWatchFlowController?.prepareRecentWatch(entry, settingsStore: settingsStore)
    }

    func updatePendingFolderWatchRequest(
        _ update: (inout FolderWatchFlowController.PendingFolderWatchRequest) -> Void
    ) {
        folderWatchFlowController?.updatePendingRequest(update)
    }

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
        favoriteMatchingSharedFolderWatchSession() != nil
    }

    func saveSharedFolderWatchAsFavorite(name: String) {
        guard let session = folderWatchFlowController?.sharedFolderWatchSession else {
            return
        }
        guard let groupStateController else { return }
        let groupSnapshot = groupStateController.persistenceSnapshot
        var workspaceState = ReaderFavoriteWorkspaceState.from(
            settings: settingsStore.currentSettings,
            pinnedGroupIDs: groupSnapshot.pinnedGroupIDs,
            collapsedGroupIDs: groupSnapshot.collapsedGroupIDs,
            sidebarWidth: sidebarWidth
        )
        workspaceState.fileSortMode = groupSnapshot.fileSortMode
        workspaceState.groupSortMode = groupSnapshot.sortMode
        workspaceState.lockedAppearance = appearanceController?.lockedAppearance
        workspaceState.manualGroupOrder = groupSnapshot.manualGroupOrder
        settingsStore.addFavoriteWatchedFolder(
            name: name,
            folderURL: session.folderURL,
            options: session.options,
            openDocumentFileURLs: currentSidebarOpenDocumentFileURLs(),
            workspaceState: workspaceState
        )

        if let created = favoriteMatchingSharedFolderWatchSession() {
            favoriteWorkspaceController?.activate(id: created.id, workspaceState: created.workspaceState)
        }
    }

    func removeSharedFolderWatchFromFavorites() {
        guard let match = favoriteMatchingSharedFolderWatchSession() else {
            return
        }
        settingsStore.removeFavoriteWatchedFolder(id: match.id)
        favoriteWorkspaceController?.deactivate()
    }

    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
        // Restore appearance FIRST so the controller is in the correct lock state
        // before activeFavoriteWorkspaceState triggers onChange persistence.
        if let lockedAppearance = entry.workspaceState.lockedAppearance {
            appearanceController?.restore(from: lockedAppearance)
        } else if appearanceController?.isLocked == true {
            appearanceController?.unlock()
        }

        // Set active favorite and restore workspace state
        favoriteWorkspaceController?.activate(id: entry.id, workspaceState: entry.workspaceState)
        groupStateController?.applyWorkspaceState(entry.workspaceState)
        sidebarWidth = entry.workspaceState.sidebarWidth

        let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry)
        startWatchingFolder(
            folderURL: resolvedURL,
            options: entry.options,
            performInitialAutoOpen: false
        )

        let restoredFileURLs = entry.existingOpenDocumentFileURLs(relativeTo: resolvedURL)
        if let session = folderWatchFlowController?.sharedFolderWatchSession,
           !restoredFileURLs.isEmpty {
            fileOpenCoordinator.open(FileOpenRequest(
                fileURLs: restoredFileURLs,
                origin: .folderWatchInitialBatchAutoOpen,
                folderWatchSession: session,
                slotStrategy: .reuseEmptySlotForFirst,
                materializationStrategy: .deferThenMaterializeNewest(count: ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
            ))
            refreshWindowPresentation()
        }

        syncSharedFavoriteOpenDocumentsIfNeeded()

        if entry.options.openMode == .openAllMarkdownFiles {
            discoverNewFilesForFavorite(entry, resolvedFolderURL: resolvedURL)
        }
    }

    private func discoverNewFilesForFavorite(
        _ entry: ReaderFavoriteWatchedFolder,
        resolvedFolderURL: URL
    ) {
        sidebarDocumentController.folderWatchCoordinator.scanCurrentMarkdownFiles { [weak self] scannedURLs in
            guard let self,
                  let session = folderWatchFlowController?.sharedFolderWatchSession else {
                return
            }

            let newFileURLs = entry.newFileURLs(fromScanned: scannedURLs, relativeTo: resolvedFolderURL)
            if !newFileURLs.isEmpty {
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: newFileURLs,
                    origin: .folderWatchInitialBatchAutoOpen,
                    folderWatchSession: session,
                    slotStrategy: .alwaysAppend,
                    materializationStrategy: .deferOnly
                ))
                sidebarDocumentController.selectDocumentWithNewestModificationDate()
                refreshWindowPresentation()
            }

            settingsStore.updateFavoriteWatchedFolderKnownDocuments(
                id: entry.id,
                folderURL: resolvedFolderURL,
                knownDocumentFileURLs: scannedURLs
            )
        }
    }

    func syncSharedFavoriteOpenDocumentsIfNeeded() {
        guard let session = folderWatchFlowController?.sharedFolderWatchSession,
              let favorite = favoriteMatchingSharedFolderWatchSession() else {
            return
        }

        settingsStore.updateFavoriteWatchedFolderOpenDocuments(
            id: favorite.id,
            folderURL: session.folderURL,
            openDocumentFileURLs: currentSidebarOpenDocumentFileURLs()
        )
    }

    func favoriteMatchingSharedFolderWatchSession() -> ReaderFavoriteWatchedFolder? {
        guard let session = folderWatchFlowController?.sharedFolderWatchSession else {
            return nil
        }
        return favoriteWorkspaceController?.matchingFavorite(
            folderURL: session.folderURL,
            options: session.options,
            in: settingsStore.currentSettings.favoriteWatchedFolders
        )
    }

    func currentSidebarOpenDocumentFileURLs() -> [URL] {
        sidebarDocumentController.documents.compactMap { $0.readerStore.document.fileURL }
    }

    func clearFavoriteWatchedFolders() {
        settingsStore.clearFavoriteWatchedFolders()
    }

    func startRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        prepareRecentFolderWatch(entry)
    }

    func clearRecentWatchedFolders() {
        settingsStore.clearRecentWatchedFolders()
    }

    func clearRecentManuallyOpenedFiles() {
        settingsStore.clearRecentManuallyOpenedFiles()
    }

    func startWatchingFolder(
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) {
        // Clear active favorite - if this is a favorite watch, startFavoriteWatch sets these BEFORE calling this method
        if favoriteWorkspaceController?.activeFavoriteID != nil {
            // Only clear if this is NOT being called from startFavoriteWatch
            // (startFavoriteWatch sets activeFavoriteID before calling startWatchingFolder)
            // We can detect this by checking if the folder matches the active favorite
            let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path
            let matchesActiveFavorite = settingsStore.currentSettings.favoriteWatchedFolders.contains {
                $0.id == favoriteWorkspaceController?.activeFavoriteID && $0.matches(folderPath: normalizedPath, options: options)
            }
            if !matchesActiveFavorite {
                favoriteWorkspaceController?.persistFinalState(to: settingsStore)
                favoriteWorkspaceController?.deactivate()
                groupStateController?.pinnedGroupIDs = []
                groupStateController?.collapsedGroupIDs = []
                sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
                Task { @MainActor [appearanceController] in
                    if appearanceController?.isLocked == true {
                        appearanceController?.unlock()
                    }
                }
            }
        }

        do {
            try sidebarDocumentController.folderWatchCoordinator.startWatchingFolder(
                folderURL: folderURL,
                options: options,
                performInitialAutoOpen: performInitialAutoOpen
            )
        } catch {
            sidebarDocumentController.selectedReaderStore.presentError(error)
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
        guard let session = folderWatchFlowController?.sharedFolderWatchSession else { return false }

        let normalizedOld = Set(
            session.options.encodedForFolder(session.folderURL).excludedSubdirectoryPaths
        )
        let normalizedNew = Set(
            ReaderFolderWatchOptions(
                openMode: session.options.openMode,
                scope: session.options.scope,
                excludedSubdirectoryPaths: newExcludedPaths
            ).encodedForFolder(session.folderURL).excludedSubdirectoryPaths
        )

        guard normalizedOld != normalizedNew else { return true }

        syncFavoriteExclusionsIfNeeded(newExcludedPaths)

        do {
            try sidebarDocumentController.folderWatchCoordinator.updateFolderWatchExcludedSubdirectories(newExcludedPaths)
        } catch {
            sidebarDocumentController.selectedReaderStore.presentError(error)
            return false
        }

        let newlyExcludedPaths = normalizedNew.subtracting(normalizedOld)
        if !newlyExcludedPaths.isEmpty {
            folderWatchFlowController?.closeDocumentsInExcludedPaths(Array(newlyExcludedPaths))
        }

        let newlyIncludedPaths = normalizedOld.subtracting(normalizedNew)
        if !newlyIncludedPaths.isEmpty, session.options.openMode == .openAllMarkdownFiles {
            folderWatchFlowController?.openFilesInNewlyIncludedPaths(Array(newlyIncludedPaths), fileOpenCoordinator: fileOpenCoordinator)
        }

        refreshWindowPresentation()
        return true
    }

    private func syncFavoriteExclusionsIfNeeded(_ excludedPaths: [String]) {
        guard let favoriteID = favoriteWorkspaceController?.activeFavoriteID else { return }
        settingsStore.updateFavoriteWatchedFolderExclusions(
            id: favoriteID,
            excludedSubdirectoryPaths: excludedPaths
        )
    }

    func persistFinalWorkspaceStateIfNeeded() {
        favoriteWorkspaceController?.persistFinalState(to: settingsStore)
    }

    // MARK: - Warning Flow

    func cancelFolderWatch() {
        folderWatchFlowController?.cancelPendingWatch()
    }

    func confirmFolderWatch(_ options: ReaderFolderWatchOptions) {
        guard let folderURL = folderWatchFlowController?.pendingFolderWatchRequest?.folderURL else {
            return
        }

        startWatchingFolder(folderURL: folderURL, options: options)
        cancelFolderWatch()
    }

    func stopFolderWatch() {
        dismissFolderWatchAutoOpenWarning()
        favoriteWorkspaceController?.persistFinalState(to: settingsStore)
        favoriteWorkspaceController?.deactivate()
        groupStateController?.pinnedGroupIDs = []
        groupStateController?.collapsedGroupIDs = []
        sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        sidebarDocumentController.folderWatchCoordinator.stopFolderWatch()
        refreshWindowPresentation()
        cancelFolderWatch()
    }

    func handleFolderWatchAutoOpenWarningChange(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchFlowController?.handleAutoOpenWarningChange(warning) { [weak self] in
            self?.isFolderWatchWarningPresentationAllowed() ?? false
        }
    }

    func refreshFolderWatchAutoOpenWarningPresentation() {
        folderWatchFlowController?.refreshAutoOpenWarningPresentation { [weak self] in
            self?.isFolderWatchWarningPresentationAllowed() ?? false
        }
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchFlowController?.dismissAutoOpenWarning()
    }

    func openSelectedFolderWatchAutoOpenFiles() {
        folderWatchFlowController?.openSelectedAutoOpenFiles(using: fileOpenCoordinator)
        refreshWindowPresentation()
    }

    func isFolderWatchWarningPresentationAllowed() -> Bool {
        folderWatchFlowController?.isWarningPresentationAllowed(hostWindow: hostWindow) ?? false
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
            saveSharedFolderWatchAsFavorite(name: name)
        case .removeCurrentWatchFromFavorites:
            removeSharedFolderWatchFromFavorites()
        case .toggleAppearanceLock:
            toggleAppearanceLock()
        case .startFavoriteWatch(let fav):
            startFavoriteWatch(fav)
        case .clearFavoriteWatchedFolders:
            clearFavoriteWatchedFolders()
        case .renameFavoriteWatchedFolder(let id, let name):
            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
        case .removeFavoriteWatchedFolder(let id):
            settingsStore.removeFavoriteWatchedFolder(id: id)
        case .reorderFavoriteWatchedFolders(let ids):
            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
        case .startRecentManuallyOpenedFile(let entry):
            let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
            fileOpenCoordinator.open(FileOpenRequest(
                fileURLs: [resolvedURL], origin: .manual,
                folderWatchSession: folderWatchFlowController?.sharedFolderWatchSession,
                slotStrategy: .replaceSelectedSlot
            ))
            applyWindowTitlePresentation()
        case .startRecentFolderWatch(let entry):
            startRecentFolderWatch(entry)
        case .clearRecentWatchedFolders:
            clearRecentWatchedFolders()
        case .clearRecentManuallyOpenedFiles:
            clearRecentManuallyOpenedFiles()
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

    // MARK: - UI Test Flow

    func applyUITestLaunchConfigurationIfNeeded() {
        guard !hasAppliedUITestLaunchConfiguration else {
            return
        }

        let action = resolvedUITestLaunchAction()
        switch action {
        case .none:
            break
        case .simulateGroupedSidebar:
            startUITestGroupedSidebarFlow()
        case .simulateAutoOpenWatchFlow:
            startUITestAutoOpenWatchFlow()
        case .presentWatchFolderSheet(let watchFolderURL):
            applyScreenshotWindowSize()
            var options = ReaderFolderWatchOptions.default
            if ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
            ] == "includeSubfolders" {
                options.scope = .includeSubfolders
            }
            presentFolderWatchOptions(for: watchFolderURL, options: options)
        case .startWatchingFolder(let watchFolderURL):
            startWatchingFolder(folderURL: watchFolderURL, options: .default)
        }
        hasAppliedUITestLaunchConfiguration = true
    }

    private func resolvedUITestLaunchAction() -> ReaderWindowUITestLaunchAction {
        ReaderWindowUITestFlowSupport.resolveLaunchAction(
            configuration: ReaderUITestLaunchConfiguration.current,
            hostWindowAvailable: hostWindow != nil
        )
    }

    private func applyScreenshotWindowSize() {
        guard let sizeStr = ProcessInfo.processInfo.environment[
            ReaderUITestLaunchConfiguration.screenshotWindowSizeEnvironmentKey
        ], !sizeStr.isEmpty else { return }

        let parts = sizeStr.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }

        if let window = hostWindow {
            let frame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: parts[0],
                height: parts[1]
            )
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func startUITestGroupedSidebarFlow() {
        ReaderWindowUITestFlowSupport.startGroupedSidebarFlow { [self] fileURLs in
            openFileRequest(FileOpenRequest(
                fileURLs: fileURLs,
                origin: .manual
            ))
        }
    }

    private func startUITestAutoOpenWatchFlow() {
        ReaderWindowUITestFlowSupport.startAutoOpenWatchFlow(
            startWatchingFolder: { [self] watchFolderURL in
                startWatchingFolder(folderURL: watchFolderURL, options: .default)
            },
            cancelExistingTask: { [self] in
                uiTestWatchFlowTask?.cancel()
            },
            waitForFolderWatchStartup: { [folderWatchFlowController] in
                await ReaderWindowUITestFlowSupport.waitForFolderWatchStartup {
                    folderWatchFlowController?.sharedFolderWatchSession != nil
                }
            },
            assignTask: { [self] task in
                uiTestWatchFlowTask = task
            }
        )
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
