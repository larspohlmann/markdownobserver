import AppKit
import SwiftUI

struct ReaderWindowRootView: View {
    struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: ReaderFolderWatchOptions
    }

    let seed: ReaderWindowSeed?
    var settingsStore: ReaderSettingsStore
    let multiFileDisplayMode: ReaderMultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @State var sidebarDocumentController: ReaderSidebarDocumentController
    @State private var hasOpenedInitialFile = false
    @State var hostWindow: NSWindow?
    @State var isFolderWatchOptionsPresented = false
    @State var pendingFolderWatchRequest: PendingFolderWatchRequest?
    @State var sharedFolderWatchSession: ReaderFolderWatchSession?
    @State var canStopSharedFolderWatch = false
    @State private var uiTestWatchFlowTask: Task<Void, Never>?
    @State private var hasAppliedUITestLaunchConfiguration = false
    @State var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    @State var groupStateController = SidebarGroupStateController()
    @State var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    @State private var lastAppliedSidebarDelta: CGFloat = 0
    @State var activeFavoriteID: UUID?
    @State var activeFavoriteWorkspaceState: ReaderFavoriteWorkspaceState?
    @State var windowCoordinator: ReaderWindowCoordinator
    @State var appearanceController: WindowAppearanceController
    @State var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()
    @State private var isTitlebarEditingFavorites = false
    @State var isEditingSubfolders = false
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
    }

    private var sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement {
        let effectiveMode = activeFavoriteWorkspaceState?.sidebarPosition ?? multiFileDisplayMode
        return effectiveMode.sidebarPlacement
    }

    private var pendingFolderWatchURL: URL? {
        pendingFolderWatchRequest?.folderURL
    }

    private var openSidebarDocumentPathSnapshot: Set<String> {
        Set(currentSidebarOpenDocumentFileURLs().map(\.path))
    }

    private var pendingFolderWatchOpenModeBinding: Binding<ReaderFolderWatchOpenMode> {
        Binding(
            get: {
                pendingFolderWatchRequest?.options.openMode ?? ReaderFolderWatchOptions.default.openMode
            },
            set: { newValue in
                updatePendingFolderWatchRequest { request in
                    request.options.openMode = newValue
                }
            }
        )
    }

    private var pendingFolderWatchScopeBinding: Binding<ReaderFolderWatchScope> {
        Binding(
            get: {
                pendingFolderWatchRequest?.options.scope ?? ReaderFolderWatchOptions.default.scope
            },
            set: { newValue in
                updatePendingFolderWatchRequest { request in
                    request.options.scope = newValue
                }
            }
        )
    }

    private var pendingFolderWatchExcludedSubdirectoryPathsBinding: Binding<[String]> {
        Binding(
            get: {
                pendingFolderWatchRequest?.options.excludedSubdirectoryPaths ?? []
            },
            set: { newValue in
                updatePendingFolderWatchRequest { request in
                    request.options.excludedSubdirectoryPaths = newValue
                }
            }
        )
    }

    var body: some View {
        commandNotificationAwareView(windowLifecycleAwareView(rootContent))
    }

    private func windowLifecycleAwareView<Content: View>(_ view: Content) -> some View {
        windowLifecycleChangeObservers(windowLifecycleBaseView(view))
    }

    private func windowLifecycleBaseView<Content: View>(_ view: Content) -> some View {
        @Bindable var warningCoordinator = folderWatchWarningCoordinator
        @Bindable var sidebarController = sidebarDocumentController
        return view
            .sheet(item: $warningCoordinator.activeFlow, onDismiss: {
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
            .sheet(item: $sidebarController.pendingFileSelectionRequest, onDismiss: {
                sidebarDocumentController.dismissPendingFileSelectionRequest()
            }) { request in
                FolderWatchFileSelectionSheetWrapper(
                    request: request,
                    onSkip: {
                        sidebarDocumentController.dismissPendingFileSelectionRequest()
                    },
                    onConfirm: { selectedFileURLs in
                        sidebarDocumentController.dismissPendingFileSelectionRequest()
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
            .sheet(isPresented: $isTitlebarEditingFavorites) {
                EditFavoritesSheet(
                    favorites: settingsStore.currentSettings.favoriteWatchedFolders,
                    onRename: { id, newName in
                        settingsStore.renameFavoriteWatchedFolder(id: id, newName: newName)
                    },
                    onDelete: { id in
                        settingsStore.removeFavoriteWatchedFolder(id: id)
                    },
                    onReorder: { orderedIDs in
                        settingsStore.reorderFavoriteWatchedFolders(orderedIDs: orderedIDs)
                    },
                    onDismiss: { isTitlebarEditingFavorites = false }
                )
            }
            .sheet(isPresented: $isEditingSubfolders) {
                if let session = sharedFolderWatchSession {
                    EditFolderWatchSheet(
                        folderURL: session.folderURL,
                        currentExcludedSubdirectoryPaths: session.options.excludedSubdirectoryPaths,
                        onConfirm: { newExclusions in
                            if updateFolderWatchExclusions(newExclusions) {
                                isEditingSubfolders = false
                            }
                        },
                        onCancel: {
                            isEditingSubfolders = false
                        }
                    )
                }
            }
            .background(
                WindowAccessor { window in
                    handleWindowAccessorUpdate(window)
                }
            )
            .navigationTitle(effectiveWindowTitle)
            .task {
                performInitialSetupIfNeeded()
            }
            .onOpenURL { url in
                openIncomingURL(url)
            }
            .onChange(of: hostWindow) { _, _ in
                handleHostWindowStateChange()
            }
            .onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
                applyWindowTitlePresentation()
                renderSelectedDocumentIfNeeded()
            }
            .onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
                let isSidebarVisible = newCount > 1
                let wasVisible = oldCount > 1

                guard isSidebarVisible != wasVisible, let window = hostWindow else {
                    return
                }

                if isSidebarVisible, let favoriteWidth = activeFavoriteWorkspaceState?.sidebarWidth {
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
            .onChange(of: sidebarDocumentController.selectedWindowTitle) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: sidebarDocumentController.selectedHasUnacknowledgedExternalChange) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: sharedFolderWatchSession) { _, _ in
                refreshWindowShellRegistrationAndTitle()
                syncSharedFavoriteOpenDocumentsIfNeeded()
            }
            .onChange(of: openSidebarDocumentPathSnapshot) { _, _ in
                syncSharedFavoriteOpenDocumentsIfNeeded()
            }
    }

    private func windowLifecycleChangeObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: sidebarDocumentController.selectedFolderWatchAutoOpenWarning) { _, warning in
                handleFolderWatchAutoOpenWarningChange(warning)
            }
            .onChange(of: sidebarDocumentController.activeFolderWatchSession) { _, _ in
                refreshWindowShellState()
            }
            .onChange(of: isFolderWatchOptionsPresented) { _, isPresented in
                handleFolderWatchOptionsPresentationChange(isPresented)
            }
            .onChange(of: groupStateController.persistenceSnapshot) { oldSnapshot, newSnapshot in
                if var state = activeFavoriteWorkspaceState {
                    let needsUpdate =
                        state.pinnedGroupIDs != newSnapshot.pinnedGroupIDs ||
                        state.collapsedGroupIDs != newSnapshot.collapsedGroupIDs ||
                        state.groupSortMode != newSnapshot.sortMode ||
                        state.fileSortMode != newSnapshot.fileSortMode

                    if needsUpdate {
                        state.pinnedGroupIDs = newSnapshot.pinnedGroupIDs
                        state.collapsedGroupIDs = newSnapshot.collapsedGroupIDs
                        state.groupSortMode = newSnapshot.sortMode
                        state.fileSortMode = newSnapshot.fileSortMode
                        activeFavoriteWorkspaceState = state
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
            }
            .onChange(of: appearanceController.effectiveAppearance) { _, _ in
                reapplyAppearance()
            }
            .onChange(of: activeFavoriteWorkspaceState) { _, newState in
                guard let favoriteID = activeFavoriteID, var state = newState else {
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
        guard !hasOpenedInitialFile else {
            return
        }

        hasOpenedInitialFile = true
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
        if window == nil, let hostWindow {
            ReaderWindowRegistry.shared.unregisterWindow(hostWindow)
        }

        hostWindow = window
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
              window === hostWindow else {
            return
        }

        refreshWindowPresentation()
        refreshFolderWatchAutoOpenWarningPresentation()
    }

    private func commandNotificationAwareView<Content: View>(_ view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.openRecentFile)) { notification in
                guard let payload = ReaderCommandNotification.Payload(notification: notification),
                      payload.targetWindowNumber == hostWindow?.windowNumber else {
                    return
                }

                guard let entry = payload.recentFileEntry else {
                    return
                }

                let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: [resolvedURL],
                    origin: .manual,
                    folderWatchSession: sharedFolderWatchSession,
                    slotStrategy: .replaceSelectedSlot
                ))
                applyWindowTitlePresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.prepareRecentWatchedFolder)) { notification in
                guard let payload = ReaderCommandNotification.Payload(notification: notification),
                      payload.targetWindowNumber == hostWindow?.windowNumber else {
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
            sidebarWidth: sidebarWidth,
            onSidebarWidthChanged: { newWidth in
                sidebarWidth = newWidth
                if activeFavoriteWorkspaceState != nil,
                   sidebarDocumentController.documents.count > 1 {
                    activeFavoriteWorkspaceState?.sidebarWidth = newWidth
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
                    activeFolderWatch: sharedFolderWatchSession,
                    isInitialScanInProgress: sidebarDocumentController.isFolderWatchInitialScanInProgress,
                    didInitialScanFail: sidebarDocumentController.didFolderWatchInitialScanFail,
                    favoriteWatchedFolders: settingsStore.currentSettings.favoriteWatchedFolders,
                    recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
                    onActivate: {
                        promptForFolderWatch()
                    },
                    onStartFavoriteWatch: { favorite in
                        startFavoriteWatch(favorite)
                    },
                    onStartRecentFolderWatch: { recent in
                        startRecentFolderWatch(recent)
                    },
                    onEditFavoriteWatchedFolders: {
                        isTitlebarEditingFavorites = true
                    },
                    onClearRecentWatchedFolders: {
                        clearRecentWatchedFolders()
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
        ContentViewAdapter(
            readerStore: store,
            sidebarDocumentController: sidebarDocumentController,
            settingsStore: settingsStore,
            appearanceController: appearanceController,
            sharedFolderWatchSession: sharedFolderWatchSession,
            canStopSharedFolderWatch: canStopSharedFolderWatch,
            pendingFolderWatchURL: pendingFolderWatchURL,
            callbacks: ContentViewCallbacks(
                onRequestFileOpen: { [self] request in
                    fileOpenCoordinator.open(request)
                    refreshWindowPresentation()
                },
                onRequestFolderWatch: prepareFolderWatchOptions,
                onConfirmFolderWatch: confirmFolderWatch,
                onCancelFolderWatch: cancelFolderWatch,
                onStopFolderWatch: stopFolderWatch,
                onSaveFolderWatchAsFavorite: { name in
                    saveSharedFolderWatchAsFavorite(name: name)
                },
                onRemoveCurrentWatchFromFavorites: {
                    removeSharedFolderWatchFromFavorites()
                },
                onToggleAppearanceLock: {
                    if appearanceController.isLocked {
                        appearanceController.unlock()
                        for document in sidebarDocumentController.documents {
                            document.readerStore.clearAppearanceOverride()
                        }
                        if activeFavoriteWorkspaceState != nil {
                            activeFavoriteWorkspaceState?.lockedAppearance = nil
                        }
                    } else {
                        appearanceController.lock()
                        let appearance = appearanceController.effectiveAppearance
                        for document in sidebarDocumentController.documents {
                            document.readerStore.setAppearanceOverride(appearance)
                        }
                        if activeFavoriteWorkspaceState != nil {
                            activeFavoriteWorkspaceState?.lockedAppearance = appearanceController.lockedAppearance
                        }
                    }
                },
                onStartFavoriteWatch: startFavoriteWatch,
                onClearFavoriteWatchedFolders: clearFavoriteWatchedFolders,
                onRenameFavoriteWatchedFolder: { id, newName in
                    settingsStore.renameFavoriteWatchedFolder(id: id, newName: newName)
                },
                onRemoveFavoriteWatchedFolder: { id in
                    settingsStore.removeFavoriteWatchedFolder(id: id)
                },
                onReorderFavoriteWatchedFolders: { orderedIDs in
                    settingsStore.reorderFavoriteWatchedFolders(orderedIDs: orderedIDs)
                },
                onStartRecentManuallyOpenedFile: { entry in
                    let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
                    fileOpenCoordinator.open(FileOpenRequest(
                        fileURLs: [resolvedURL],
                        origin: .manual,
                        folderWatchSession: sharedFolderWatchSession,
                        slotStrategy: .replaceSelectedSlot
                    ))
                    applyWindowTitlePresentation()
                },
                onStartRecentFolderWatch: startRecentFolderWatch,
                onClearRecentWatchedFolders: clearRecentWatchedFolders,
                onClearRecentManuallyOpenedFiles: clearRecentManuallyOpenedFiles,
                onEditSubfolders: {
                    isEditingSubfolders = true
                }
            ),
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenModeBinding,
            pendingFolderWatchScope: pendingFolderWatchScopeBinding,
            pendingFolderWatchExcludedSubdirectoryPaths: pendingFolderWatchExcludedSubdirectoryPathsBinding
        )
    }

    private func handleHostWindowStateChange() {
        refreshWindowShellState()
        applyUITestLaunchConfigurationIfNeeded()

        guard hostWindow != nil,
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
        guard !hasAppliedUITestLaunchConfiguration else {
            return
        }

        let action = resolvedUITestLaunchAction()
        guard case .none = action else {
            switch action {
            case .none:
                hasAppliedUITestLaunchConfiguration = true
            case .simulateGroupedSidebar:
                startUITestGroupedSidebarFlow()
                hasAppliedUITestLaunchConfiguration = true
            case .simulateAutoOpenWatchFlow:
                startUITestAutoOpenWatchFlow()
                hasAppliedUITestLaunchConfiguration = true
            case .presentWatchFolderSheet(let watchFolderURL):
                applyScreenshotWindowSize()
                var options = ReaderFolderWatchOptions.default
                if ProcessInfo.processInfo.environment[
                    ReaderUITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
                ] == "includeSubfolders" {
                    options.scope = .includeSubfolders
                }
                presentFolderWatchOptions(for: watchFolderURL, options: options)
                hasAppliedUITestLaunchConfiguration = true
            case .startWatchingFolder(let watchFolderURL):
                startWatchingFolder(folderURL: watchFolderURL, options: .default)
                hasAppliedUITestLaunchConfiguration = true
            }
            return
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
            cancelExistingTask: {
                uiTestWatchFlowTask?.cancel()
            },
            waitForFolderWatchStartup: {
                await waitForUITestFolderWatchStartup()
            },
            assignTask: { task in
                uiTestWatchFlowTask = task
            }
        )
    }

    private func waitForUITestFolderWatchStartup() async {
        await ReaderWindowUITestFlowSupport.waitForFolderWatchStartup {
            sharedFolderWatchSession != nil
        }
    }

}
