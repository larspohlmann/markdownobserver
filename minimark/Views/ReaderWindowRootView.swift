import AppKit
import SwiftUI

struct ReaderWindowRootView: View {
    let seed: ReaderWindowSeed?
    var settingsStore: ReaderSettingsStore
    let multiFileDisplayMode: ReaderMultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @State var sidebarDocumentController: ReaderSidebarDocumentController
    @State var windowCoordinator: ReaderWindowCoordinator
    @State var appearanceController: WindowAppearanceController
    @State var groupStateController = SidebarGroupStateController()
    @State var favoriteWorkspaceController = FavoriteWorkspaceController()
    @State var folderWatchFlowController: FolderWatchFlowController

    var fileOpenCoordinator: FileOpenCoordinator {
        sidebarDocumentController.fileOpenCoordinator
    }

    init(
        seed: ReaderWindowSeed?,
        settingsStore: ReaderSettingsStore,
        multiFileDisplayMode: ReaderMultiFileDisplayMode
    ) {
        self.seed = seed
        self.settingsStore = settingsStore
        self.multiFileDisplayMode = multiFileDisplayMode
        let sidebarDocumentController = ReaderSidebarDocumentController(settingsStore: settingsStore)
        _sidebarDocumentController = State(wrappedValue: sidebarDocumentController)
        _windowCoordinator = State(
            wrappedValue: ReaderWindowCoordinator(
                settingsStore: settingsStore,
                sidebarDocumentController: sidebarDocumentController
            )
        )
        _appearanceController = State(
            wrappedValue: WindowAppearanceController(settingsStore: settingsStore)
        )
        _folderWatchFlowController = State(
            wrappedValue: FolderWatchFlowController(sidebarDocumentController: sidebarDocumentController)
        )
    }

    private var sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement {
        let effectiveMode = favoriteWorkspaceController.activeFavoriteWorkspaceState?.sidebarPosition ?? multiFileDisplayMode
        return effectiveMode.sidebarPlacement
    }

    private var openSidebarDocumentPathSnapshot: Set<String> {
        Set(currentSidebarOpenDocumentFileURLs().map(\.path))
    }

    private var pendingFolderWatchOpenModeBinding: Binding<ReaderFolderWatchOpenMode> {
        Binding(
            get: { [folderWatchFlowController] in
                folderWatchFlowController.pendingFolderWatchRequest?.options.openMode ?? ReaderFolderWatchOptions.default.openMode
            },
            set: { [folderWatchFlowController] newValue in
                folderWatchFlowController.updatePendingRequest { request in
                    request.options.openMode = newValue
                }
            }
        )
    }

    private var pendingFolderWatchScopeBinding: Binding<ReaderFolderWatchScope> {
        Binding(
            get: { [folderWatchFlowController] in
                folderWatchFlowController.pendingFolderWatchRequest?.options.scope ?? ReaderFolderWatchOptions.default.scope
            },
            set: { [folderWatchFlowController] newValue in
                folderWatchFlowController.updatePendingRequest { request in
                    request.options.scope = newValue
                }
            }
        )
    }

    private var pendingFolderWatchExcludedSubdirectoryPathsBinding: Binding<[String]> {
        Binding(
            get: { [folderWatchFlowController] in
                folderWatchFlowController.pendingFolderWatchRequest?.options.excludedSubdirectoryPaths ?? []
            },
            set: { [folderWatchFlowController] newValue in
                folderWatchFlowController.updatePendingRequest { request in
                    request.options.excludedSubdirectoryPaths = newValue
                }
            }
        )
    }

    var body: some View {
        if windowCoordinator.hasCompletedWindowPhase {
            commandNotificationAwareView(windowLifecycleAwareView(rootContent))
        } else {
            windowShell
        }
    }

    private var windowShell: some View {
        let theme = ReaderTheme.theme(for: settingsStore.currentSettings.readerTheme)
        return ZStack {
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)
            ProgressView()
                .controlSize(.large)
                .colorScheme(theme.kind.isDark ? .dark : .light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                FolderWatchToolbarButton(
                    activeFolderWatch: nil,
                    isInitialScanInProgress: false,
                    didInitialScanFail: false,
                    favoriteWatchedFolders: settingsStore.currentSettings.favoriteWatchedFolders,
                    recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
                    onAction: { _ in },
                    compact: true
                )
                .disabled(true)
                .allowsHitTesting(false)
                .padding(.trailing, 8)
            }
        }
        .navigationTitle(ReaderWindowTitleFormatter.appName)
        .task {
            await Task.yield()
            windowCoordinator.hasCompletedWindowPhase = true
        }
    }

    private func windowLifecycleAwareView<Content: View>(_ view: Content) -> some View {
        windowLifecycleChangeObservers(windowLifecycleBaseView(view))
    }

    private func windowLifecycleBaseView<Content: View>(_ view: Content) -> some View {
        @Bindable var warningCoord = folderWatchFlowController.warningCoordinator
        @Bindable var folderWatchCoordinator = sidebarDocumentController.folderWatchCoordinator
        @Bindable var coordinator = windowCoordinator
        @Bindable var folderWatchFlow = folderWatchFlowController
        return view
            .sheet(item: $warningCoord.activeFlow, onDismiss: {
                dismissFolderWatchAutoOpenWarning()
            }) { flow in
                FolderWatchAutoOpenWarningFlowSheet(
                    flow: flow,
                    onKeepCurrentFiles: {
                        dismissFolderWatchAutoOpenWarning()
                    },
                    onOpenSelectedFiles: {
                        openSelectedFolderWatchAutoOpenFiles()
                    }
                )
            }
            .sheet(item: $folderWatchCoordinator.pendingFileSelectionRequest, onDismiss: {
                sidebarDocumentController.folderWatchCoordinator.dismissPendingFileSelectionRequest()
            }) { request in
                FolderWatchFileSelectionSheetWrapper(
                    request: request,
                    onSkip: {
                        sidebarDocumentController.folderWatchCoordinator.dismissPendingFileSelectionRequest()
                    },
                    onConfirm: { selectedFileURLs in
                        sidebarDocumentController.folderWatchCoordinator.dismissPendingFileSelectionRequest()
                        fileOpenCoordinator.open(FileOpenRequest(
                            fileURLs: selectedFileURLs,
                            origin: .folderWatchInitialBatchAutoOpen,
                            folderWatchSession: request.session,
                            slotStrategy: .reuseEmptySlotForFirst,
                            materializationStrategy: .deferThenMaterializeSelected
                        ))
                        refreshWindowPresentation()
                    }
                )
            }
            .sheet(isPresented: $coordinator.isTitlebarEditingFavorites) {
                EditFavoritesSheet(
                    favorites: settingsStore.currentSettings.favoriteWatchedFolders,
                    onAction: { action in
                        switch action {
                        case .rename(let id, let name):
                            settingsStore.renameFavoriteWatchedFolder(id: id, newName: name)
                        case .delete(let id):
                            settingsStore.removeFavoriteWatchedFolder(id: id)
                        case .reorder(let ids):
                            settingsStore.reorderFavoriteWatchedFolders(orderedIDs: ids)
                        case .dismiss:
                            windowCoordinator.isTitlebarEditingFavorites = false
                        }
                    }
                )
            }
            .sheet(isPresented: $coordinator.isEditingSubfolders) {
                if let session = folderWatchFlowController.sharedFolderWatchSession {
                    EditFolderWatchSheet(
                        folderURL: session.folderURL,
                        currentExcludedSubdirectoryPaths: session.options.excludedSubdirectoryPaths,
                        onConfirm: { newExclusions in
                            if updateFolderWatchExclusions(newExclusions) {
                                windowCoordinator.isEditingSubfolders = false
                            }
                        },
                        onCancel: {
                            windowCoordinator.isEditingSubfolders = false
                        }
                    )
                }
            }
            .background(
                WindowAccessor { window in
                    handleWindowAccessorUpdate(window)
                }
            )
            .navigationTitle(windowCoordinator.effectiveWindowTitle)
            .task {
                performInitialSetupIfNeeded()
            }
            .onOpenURL { url in
                openIncomingURL(url)
            }
            .onChange(of: windowCoordinator.hostWindow) { _, _ in
                handleHostWindowStateChange()
            }
            .onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
                applyWindowTitlePresentation()
                renderSelectedDocumentIfNeeded()
            }
            .onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
                let isSidebarVisible = newCount > 1
                let wasVisible = oldCount > 1

                guard isSidebarVisible != wasVisible, let window = windowCoordinator.hostWindow else {
                    return
                }

                if isSidebarVisible, let favoriteWidth = favoriteWorkspaceController.activeFavoriteWorkspaceState?.sidebarWidth {
                    windowCoordinator.sidebarWidth = favoriteWidth
                }

                let delta = isSidebarVisible
                    ? windowCoordinator.sidebarWidth
                    : -windowCoordinator.lastAppliedSidebarDelta

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
                    windowCoordinator.lastAppliedSidebarDelta = newFrame.width - oldWidth
                } else {
                    windowCoordinator.lastAppliedSidebarDelta = 0
                    windowCoordinator.sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
                }
            }
            .onChange(of: sidebarDocumentController.selectedWindowTitle) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: sidebarDocumentController.selectedHasUnacknowledgedExternalChange) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: folderWatchFlowController.sharedFolderWatchSession) { _, _ in
                refreshWindowShellRegistrationAndTitle()
                syncSharedFavoriteOpenDocumentsIfNeeded()
            }
            .onChange(of: openSidebarDocumentPathSnapshot) { _, _ in
                syncSharedFavoriteOpenDocumentsIfNeeded()
            }
    }

    private func windowLifecycleChangeObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning) { _, warning in
                handleFolderWatchAutoOpenWarningChange(warning)
            }
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession) { _, _ in
                refreshWindowShellState()
            }
            .onChange(of: folderWatchFlowController.isFolderWatchOptionsPresented) { _, isPresented in
                handleFolderWatchOptionsPresentationChange(isPresented)
            }
            .onChange(of: groupStateController.persistenceSnapshot) { oldSnapshot, newSnapshot in
                if favoriteWorkspaceController.activeFavoriteWorkspaceState != nil {
                    favoriteWorkspaceController.updateGroupState(
                        pinnedGroupIDs: newSnapshot.pinnedGroupIDs,
                        collapsedGroupIDs: newSnapshot.collapsedGroupIDs,
                        groupSortMode: newSnapshot.sortMode,
                        fileSortMode: newSnapshot.fileSortMode,
                        manualGroupOrder: newSnapshot.manualGroupOrder
                    )
                } else {
                    if oldSnapshot.sortMode != newSnapshot.sortMode {
                        settingsStore.updateSidebarGroupSortMode(newSnapshot.sortMode)
                    }
                    if oldSnapshot.fileSortMode != newSnapshot.fileSortMode {
                        settingsStore.updateSidebarSortMode(newSnapshot.fileSortMode)
                    }
                }
            }
            .onChange(of: sidebarDocumentController.documents.map(\.id)) { _, _ in
                groupStateController.updateDocuments(
                    sidebarDocumentController.documents,
                    rowStates: sidebarDocumentController.rowStates
                )
            }
            .onAppear {
                groupStateController.configureSortModes(
                    sortMode: settingsStore.currentSettings.sidebarGroupSortMode,
                    fileSortMode: settingsStore.currentSettings.sidebarSortMode
                )
                groupStateController.updateDocuments(
                    sidebarDocumentController.documents,
                    rowStates: sidebarDocumentController.rowStates
                )
                groupStateController.observeRowStates(from: sidebarDocumentController)
                DockTileController.shared.configureDockTileIfNeeded()
                let dockTileToken = windowCoordinator.dockTileWindowToken
                sidebarDocumentController.onDockTileRowStatesChanged = { rowStates in
                    DockTileController.shared.updateRowStates(for: dockTileToken, rowStates: rowStates)
                }
                DockTileController.shared.updateRowStates(
                    for: dockTileToken,
                    rowStates: sidebarDocumentController.rowStates
                )
            }
            .onDisappear {
                sidebarDocumentController.onDockTileRowStatesChanged = nil
                DockTileController.shared.removeRowStates(for: windowCoordinator.dockTileWindowToken)
            }
            .onChange(of: appearanceController.effectiveAppearance) { _, _ in
                reapplyAppearance()
            }
            .onChange(of: favoriteWorkspaceController.activeFavoriteWorkspaceState) { _, newState in
                guard let favoriteID = favoriteWorkspaceController.activeFavoriteID, var state = newState else {
                    return
                }
                state.lockedAppearance = appearanceController.lockedAppearance
                settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                handleWindowDidBecomeKey(notification)
            }
    }

    private func reapplyAppearance() {
        // Defer rendering to the next main actor hop to avoid setting @Published
        // properties on ReaderStore during a SwiftUI view update cycle.
        Task { @MainActor in
            let appearance = appearanceController.effectiveAppearance
            for document in sidebarDocumentController.documents {
                let store = document.readerStore
                guard store.hasOpenDocument, !store.isDeferredDocument else { continue }

                if document.id == sidebarDocumentController.selectedDocumentID {
                    try? store.renderWithAppearance(appearance)
                } else {
                    store.setAppearanceOverride(appearance)
                }
            }
        }
    }

    private func renderSelectedDocumentIfNeeded() {
        guard let document = sidebarDocumentController.selectedDocument else { return }
        let store = document.readerStore
        guard store.needsAppearanceRender, store.hasOpenDocument, !store.isDeferredDocument else { return }
        Task { @MainActor in
            try? store.renderWithAppearance(appearanceController.effectiveAppearance)
        }
    }

    private func performInitialSetupIfNeeded() {
        guard !windowCoordinator.hasOpenedInitialFile else {
            return
        }

        windowCoordinator.hasOpenedInitialFile = true
        windowCoordinator.configure(
            appearanceController: appearanceController,
            groupStateController: groupStateController,
            favoriteWorkspaceController: favoriteWorkspaceController,
            folderWatchFlowController: folderWatchFlowController
        )
        configureStoreCallbacks()
        applyInitialSeedIfNeeded()
        refreshSharedFolderWatchState()
    }

    private func configureStoreCallbacks() {
        windowCoordinator.configureStoreCallbacks(
            lockedAppearanceProvider: { [appearanceController] in appearanceController.lockedAppearance }
        ) { [self] fileURL, folderWatchSession, origin, initialDiffBaselineMarkdown in
            let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
            if ReaderWindowRegistry.shared.focusDocumentIfAlreadyOpen(at: normalizedFileURL) {
                return
            }
            if folderWatchSession != nil {
                enqueueFolderWatchOpen(
                    folderWatchChangeEvent(for: normalizedFileURL, initialDiffBaselineMarkdown: initialDiffBaselineMarkdown),
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
    }

    private func handleWindowAccessorUpdate(_ window: NSWindow?) {
        if window == nil, let existingWindow = windowCoordinator.hostWindow {
            ReaderWindowRegistry.shared.unregisterWindow(existingWindow)
        }

        windowCoordinator.hostWindow = window
        handleHostWindowStateChange()
    }

    private func handleFolderWatchOptionsPresentationChange(_ isPresented: Bool) {
        guard !isPresented else {
            return
        }

        refreshFolderWatchAutoOpenWarningPresentation()
    }

    private func handleWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === windowCoordinator.hostWindow else {
            return
        }

        refreshWindowPresentation()
        refreshFolderWatchAutoOpenWarningPresentation()
    }

    private func commandNotificationAwareView<Content: View>(_ view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.openRecentFile)) { notification in
                guard let payload = ReaderCommandNotification.Payload(notification: notification),
                      payload.targetWindowNumber == windowCoordinator.hostWindow?.windowNumber else {
                    return
                }

                guard let entry = payload.recentFileEntry else {
                    return
                }

                let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: [resolvedURL],
                    origin: .manual,
                    folderWatchSession: folderWatchFlowController.sharedFolderWatchSession,
                    slotStrategy: .replaceSelectedSlot
                ))
                applyWindowTitlePresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.prepareRecentWatchedFolder)) { notification in
                guard let payload = ReaderCommandNotification.Payload(notification: notification),
                      payload.targetWindowNumber == windowCoordinator.hostWindow?.windowNumber else {
                    return
                }

                guard let entry = payload.recentWatchedFolderEntry else {
                    return
                }

                prepareRecentFolderWatch(entry)
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        ReaderSidebarWorkspaceView(
            controller: sidebarDocumentController,
            settingsStore: settingsStore,
            groupState: groupStateController,
            sidebarPlacement: sidebarPlacement,
            sidebarWidth: windowCoordinator.sidebarWidth,
            onSidebarWidthChanged: { newWidth in
                windowCoordinator.sidebarWidth = newWidth
                if favoriteWorkspaceController.activeFavoriteWorkspaceState != nil,
                   sidebarDocumentController.documents.count > 1 {
                    favoriteWorkspaceController.updateSidebarWidth(newWidth)
                }
            },
            detail: { store in
                contentView(for: store)
            },
            onToggleSidebarPlacement: {
                toggleSidebarPlacement()
            },
            onOpenInDefaultApp: { documentIDs in
                openSidebarDocumentsInDefaultApp(documentIDs)
            },
            onOpenInApplication: { application, documentIDs in
                openSidebarDocumentsInApplication(application, documentIDs)
            },
            onRevealInFinder: { documentIDs in
                revealSidebarDocumentsInFinder(documentIDs)
            },
            onStopWatchingFolders: { documentIDs in
                stopWatchingSidebarFolders(documentIDs)
            },
            onCloseDocuments: { documentIDs in
                closeSelectedSidebarDocuments(documentIDs)
            },
            onCloseOtherDocuments: { documentIDs in
                closeOtherSidebarDocuments(keeping: documentIDs)
            },
            onCloseAllDocuments: {
                closeAllSidebarDocuments()
            }
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                FolderWatchToolbarButton(
                    activeFolderWatch: folderWatchFlowController.sharedFolderWatchSession,
                    isInitialScanInProgress: sidebarDocumentController.folderWatchCoordinator.isFolderWatchInitialScanInProgress,
                    didInitialScanFail: sidebarDocumentController.folderWatchCoordinator.didFolderWatchInitialScanFail,
                    favoriteWatchedFolders: settingsStore.currentSettings.favoriteWatchedFolders,
                    recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
                    onAction: { action in
                        switch action {
                        case .activate:
                            promptForFolderWatch()
                        case .startFavoriteWatch(let favorite):
                            startFavoriteWatch(favorite)
                        case .startRecentFolderWatch(let recent):
                            startRecentFolderWatch(recent)
                        case .editFavoriteWatchedFolders:
                            windowCoordinator.isTitlebarEditingFavorites = true
                        case .clearRecentWatchedFolders:
                            clearRecentWatchedFolders()
                        }
                    },
                    compact: true
                )
                .padding(.trailing, 8)
            }

            ToolbarItem(placement: .primaryAction) {
                if sidebarDocumentController.documents.count > 1 {
                    Button(action: {
                        toggleSidebarPlacement()
                    }) {
                        Image(systemName: sidebarPlacement == .left ? "sidebar.right" : "sidebar.left")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .help(sidebarPlacement == .left ? "Move Sidebar Right" : "Move Sidebar Left")
                    .accessibilityLabel(sidebarPlacement == .left ? "Move Sidebar Right" : "Move Sidebar Left")
                    .accessibilityIdentifier("sidebar-placement-toggle")
                }
            }
        }
    }

    private func contentView(for store: ReaderStore) -> some View {
        @Bindable var folderWatchFlow = folderWatchFlowController
        return ContentViewAdapter(
            readerStore: store,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            appearanceController: appearanceController,
            sharedFolderWatchSession: folderWatchFlowController.sharedFolderWatchSession,
            canStopSharedFolderWatch: folderWatchFlowController.canStopSharedFolderWatch,
            pendingFolderWatchURL: folderWatchFlowController.pendingFolderWatchURL,
            onAction: { [self] action in
                switch action {
                case .requestFileOpen(let request):
                    fileOpenCoordinator.open(request)
                    refreshWindowPresentation()
                case .requestFolderWatch(let url):
                    prepareFolderWatchOptions(for: url)
                case .confirmFolderWatch(let options):
                    confirmFolderWatch(options)
                case .cancelFolderWatch:
                    cancelFolderWatch()
                case .stopFolderWatch:
                    stopFolderWatch()
                case .saveFolderWatchAsFavorite(let name):
                    saveSharedFolderWatchAsFavorite(name: name)
                case .removeCurrentWatchFromFavorites:
                    removeSharedFolderWatchFromFavorites()
                case .toggleAppearanceLock:
                    if appearanceController.isLocked {
                        appearanceController.unlock()
                        for document in sidebarDocumentController.documents {
                            document.readerStore.clearAppearanceOverride()
                        }
                        if favoriteWorkspaceController.activeFavoriteWorkspaceState != nil {
                            favoriteWorkspaceController.updateLockedAppearance(nil)
                        }
                    } else {
                        appearanceController.lock()
                        let appearance = appearanceController.effectiveAppearance
                        for document in sidebarDocumentController.documents {
                            document.readerStore.setAppearanceOverride(appearance)
                        }
                        if favoriteWorkspaceController.activeFavoriteWorkspaceState != nil {
                            favoriteWorkspaceController.updateLockedAppearance(appearanceController.lockedAppearance)
                        }
                    }
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
                        fileURLs: [resolvedURL],
                        origin: .manual,
                        folderWatchSession: folderWatchFlowController.sharedFolderWatchSession,
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
                    windowCoordinator.isEditingSubfolders = true
                }
            },
            isFolderWatchOptionsPresented: $folderWatchFlow.isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenModeBinding,
            pendingFolderWatchScope: pendingFolderWatchScopeBinding,
            pendingFolderWatchExcludedSubdirectoryPaths: pendingFolderWatchExcludedSubdirectoryPathsBinding
        )
    }

    private func handleHostWindowStateChange() {
        refreshWindowShellState()
        applyUITestLaunchConfigurationIfNeeded()

        guard windowCoordinator.hostWindow != nil,
              windowCoordinator.hasPendingFolderWatchOpenEvents else {
            return
        }

        flushQueuedFolderWatchOpens()
    }

    private func promptForFolderWatch() {
        guard let folderURL = MarkdownOpenPanel.pickFolder(
            title: "Choose Folder to Watch",
            message: "Select a folder, then choose watch options."
        ) else {
            return
        }
        prepareFolderWatchOptions(for: folderURL)
    }

    private func applyUITestLaunchConfigurationIfNeeded() {
        guard !windowCoordinator.hasAppliedUITestLaunchConfiguration else {
            return
        }

        let action = resolvedUITestLaunchAction()
        guard case .none = action else {
            switch action {
            case .none:
                windowCoordinator.hasAppliedUITestLaunchConfiguration = true
            case .simulateGroupedSidebar:
                startUITestGroupedSidebarFlow()
                windowCoordinator.hasAppliedUITestLaunchConfiguration = true
            case .simulateAutoOpenWatchFlow:
                startUITestAutoOpenWatchFlow()
                windowCoordinator.hasAppliedUITestLaunchConfiguration = true
            case .presentWatchFolderSheet(let watchFolderURL):
                applyScreenshotWindowSize()
                var options = ReaderFolderWatchOptions.default
                if ProcessInfo.processInfo.environment[
                    ReaderUITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
                ] == "includeSubfolders" {
                    options.scope = .includeSubfolders
                }
                presentFolderWatchOptions(for: watchFolderURL, options: options)
                windowCoordinator.hasAppliedUITestLaunchConfiguration = true
            case .startWatchingFolder(let watchFolderURL):
                startWatchingFolder(folderURL: watchFolderURL, options: .default)
                windowCoordinator.hasAppliedUITestLaunchConfiguration = true
            }
            return
        }
    }

    private func resolvedUITestLaunchAction() -> ReaderWindowUITestLaunchAction {
        ReaderWindowUITestFlowSupport.resolveLaunchAction(
            configuration: ReaderUITestLaunchConfiguration.current,
            hostWindowAvailable: windowCoordinator.hostWindow != nil
        )
    }

    private func applyScreenshotWindowSize() {
        guard let sizeStr = ProcessInfo.processInfo.environment[
            ReaderUITestLaunchConfiguration.screenshotWindowSizeEnvironmentKey
        ], !sizeStr.isEmpty else { return }

        let parts = sizeStr.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return }

        if let window = windowCoordinator.hostWindow {
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
        ReaderWindowUITestFlowSupport.startGroupedSidebarFlow { fileURLs in
            fileOpenCoordinator.open(FileOpenRequest(
                fileURLs: fileURLs,
                origin: .manual
            ))
            refreshWindowPresentation()
        }
    }

    private func startUITestAutoOpenWatchFlow() {
        ReaderWindowUITestFlowSupport.startAutoOpenWatchFlow(
            startWatchingFolder: { watchFolderURL in
                startWatchingFolder(folderURL: watchFolderURL, options: .default)
            },
            cancelExistingTask: { [windowCoordinator] in
                windowCoordinator.uiTestWatchFlowTask?.cancel()
            },
            waitForFolderWatchStartup: { [folderWatchFlowController] in
                await ReaderWindowUITestFlowSupport.waitForFolderWatchStartup {
                    folderWatchFlowController.sharedFolderWatchSession != nil
                }
            },
            assignTask: { [windowCoordinator] task in
                windowCoordinator.uiTestWatchFlowTask = task
            }
        )
    }

}
