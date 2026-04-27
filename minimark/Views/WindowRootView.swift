import AppKit
import SwiftUI

struct WindowRootView: View {
    let seed: WindowSeed?
    var settingsStore: SettingsStore
    let multiFileDisplayMode: MultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @State var sidebarDocumentController: SidebarDocumentController
    @State var windowCoordinator: WindowCoordinator
    @State var appearanceController: WindowAppearanceController
    @State var groupStateController: SidebarGroupStateController
    @State var favoriteWorkspaceController: FavoriteWorkspaceController
    @State var folderWatchFlowController: FolderWatchFlowController
    @State var recentHistoryCoordinator: RecentHistoryCoordinator
    @State var uiTestLaunchCoordinator: UITestLaunchCoordinator

    init(
        seed: WindowSeed?,
        settingsStore: SettingsStore,
        multiFileDisplayMode: MultiFileDisplayMode
    ) {
        self.seed = seed
        self.settingsStore = settingsStore
        self.multiFileDisplayMode = multiFileDisplayMode

        let sidebarDocumentController = SidebarDocumentController(settingsStore: settingsStore)
        let groupStateController = SidebarGroupStateController()
        let appearanceController = WindowAppearanceController(settingsStore: settingsStore)
        let uiTestLaunchCoordinator = UITestLaunchCoordinator()

        let favoriteBox = WeakBox<FavoriteWorkspaceController>()

        let folderWatchFlowController = FolderWatchFlowController(
            settingsStore: settingsStore,
            sidebarDocumentController: sidebarDocumentController,
            favoriteWorkspaceControllerProvider: { favoriteBox.value },
            groupStateControllerProvider: { [weak groupStateController] in groupStateController },
            appearanceControllerProvider: { [weak appearanceController] in appearanceController }
        )

        let favoriteWorkspaceController = FavoriteWorkspaceController(
            settingsStore: settingsStore,
            sidebarDocumentControllerProvider: { [weak sidebarDocumentController] in sidebarDocumentController },
            folderWatchFlowControllerProvider: { [weak folderWatchFlowController] in folderWatchFlowController },
            groupStateControllerProvider: { [weak groupStateController] in groupStateController },
            appearanceControllerProvider: { [weak appearanceController] in appearanceController }
        )
        favoriteBox.value = favoriteWorkspaceController

        let recentHistoryCoordinator = RecentHistoryCoordinator(settingsStore: settingsStore)

        _sidebarDocumentController = State(wrappedValue: sidebarDocumentController)
        _groupStateController = State(wrappedValue: groupStateController)
        _appearanceController = State(wrappedValue: appearanceController)
        _uiTestLaunchCoordinator = State(wrappedValue: uiTestLaunchCoordinator)
        _folderWatchFlowController = State(wrappedValue: folderWatchFlowController)
        _favoriteWorkspaceController = State(wrappedValue: favoriteWorkspaceController)
        _recentHistoryCoordinator = State(wrappedValue: recentHistoryCoordinator)
        _windowCoordinator = State(
            wrappedValue: WindowCoordinator(
                settingsStore: settingsStore,
                sidebarDocumentController: sidebarDocumentController,
                dependencies: WindowCoordinatorDependencies(
                    appearanceController: { [weak appearanceController] in appearanceController },
                    groupStateController: { [weak groupStateController] in groupStateController },
                    favoriteWorkspaceController: { [weak favoriteWorkspaceController] in favoriteWorkspaceController },
                    folderWatchFlowController: { [weak folderWatchFlowController] in folderWatchFlowController },
                    uiTestLaunchCoordinator: { [weak uiTestLaunchCoordinator] in uiTestLaunchCoordinator },
                    recentHistoryCoordinator: { [weak recentHistoryCoordinator] in recentHistoryCoordinator }
                )
            )
        )
    }

    private var sidebarPlacement: MultiFileDisplayMode.SidebarPlacement {
        let effectiveMode = favoriteWorkspaceController.activeFavoriteWorkspaceState?.sidebarPosition ?? multiFileDisplayMode
        return effectiveMode.sidebarPlacement
    }

    var body: some View {
        // `ZStack` (not `Group`) is load-bearing: on windows SwiftUI creates
        // in response to external file opens, an `if/else` inside a `Group`
        // causes `.toolbar` items to never register with the NSToolbar —
        // see #385. A stable outer container keeps the single `.toolbar`
        // modifier attached across the shell→rootContent phase transition.
        ZStack {
            if windowCoordinator.hasCompletedWindowPhase {
                commandNotificationAwareView(windowLifecycleChangeObservers(windowLifecycleBaseView(rootContent)))
            } else {
                windowShell
            }
        }
        .toolbar { windowToolbarItems }
        .environment(settingsStore)
        .environment(appearanceController)
        .environment(sidebarDocumentController)
        .environment(folderWatchFlowController)
        .environment(groupStateController)
    }

    @ToolbarContentBuilder
    private var windowToolbarItems: some ToolbarContent {
        if #available(macOS 26.0, *) {
            folderWatchToolbarItem
                .sharedBackgroundVisibility(.hidden)
            sidebarPlacementToolbarItem
                .sharedBackgroundVisibility(.hidden)
        } else {
            folderWatchToolbarItem
            sidebarPlacementToolbarItem
        }
    }

    @ToolbarContentBuilder
    private var sidebarPlacementToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            sidebarPlacementToggleButton
        }
    }

    @ToolbarContentBuilder
    private var folderWatchToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            FolderWatchToolbarButton(
                state: currentToolbarFolderWatchState,
                onAction: { action in
                    if case .activate = action {
                        promptForFolderWatch()
                    } else {
                        windowCoordinator.contentActions.handle(action)
                    }
                },
                compact: true
            )
            .disabled(!windowCoordinator.hasCompletedWindowPhase)
            .allowsHitTesting(windowCoordinator.hasCompletedWindowPhase)
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var sidebarPlacementToggleButton: some View {
        if windowCoordinator.hasCompletedWindowPhase && sidebarDocumentController.documents.count > 1 {
            Button(action: {
                windowCoordinator.sidebarActions.toggleSidebarPlacement(currentMultiFileDisplayMode: multiFileDisplayMode)
            }) {
                Image(systemName: sidebarPlacement == .left ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .help(sidebarPlacement == .left ? "Move Sidebar Right" : "Move Sidebar Left")
            .accessibilityLabel(sidebarPlacement == .left ? "Move Sidebar Right" : "Move Sidebar Left")
            .accessibilityIdentifier(.sidebarPlacementToggle)
        }
    }

    private var currentToolbarFolderWatchState: ToolbarFolderWatchState {
        let settings = settingsStore.currentSettings
        guard windowCoordinator.hasCompletedWindowPhase else {
            return ToolbarFolderWatchState(
                activeFolderWatch: nil,
                isInitialScanInProgress: false,
                didInitialScanFail: false,
                favoriteWatchedFolders: settings.favoriteWatchedFolders,
                recentWatchedFolders: settings.recentWatchedFolders
            )
        }
        let folderWatchCoordinator = sidebarDocumentController.folderWatchCoordinator
        return ToolbarFolderWatchState(
            activeFolderWatch: folderWatchFlowController.sharedFolderWatchSession,
            isInitialScanInProgress: folderWatchCoordinator.isFolderWatchInitialScanInProgress,
            didInitialScanFail: folderWatchCoordinator.didFolderWatchInitialScanFail,
            favoriteWatchedFolders: settings.favoriteWatchedFolders,
            recentWatchedFolders: settings.recentWatchedFolders
        )
    }

    private var windowShell: some View {
        let theme = Theme.theme(for: settingsStore.currentSettings.readerTheme).applyingOverride(settingsStore.currentSettings.readerThemeOverride)
        return ZStack {
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)
            ProgressView()
                .controlSize(.large)
                .colorScheme(theme.kind.isDark ? .dark : .light)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(WindowTitleFormatter.appName)
        .task {
            await Task.yield()
            windowCoordinator.hasCompletedWindowPhase = true
        }
    }

    private func windowLifecycleBaseView<Content: View>(_ view: Content) -> some View {
        @Bindable var warningCoord = folderWatchFlowController.warningCoordinator
        @Bindable var folderWatchCoordinator = sidebarDocumentController.folderWatchCoordinator
        @Bindable var coordinator = windowCoordinator
        @Bindable var folderWatchFlow = folderWatchFlowController
        return view
            .sheet(item: $warningCoord.activeFlow, onDismiss: {
                folderWatchFlowController.dismissAutoOpenWarning()
            }) { flow in
                FolderWatchAutoOpenWarningFlowSheet(
                    flow: flow,
                    onKeepCurrentFiles: {
                        folderWatchFlowController.dismissAutoOpenWarning()
                    },
                    onOpenSelectedFiles: {
                        windowCoordinator.folderWatchSession.openSelectedAutoOpenFiles()
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
                        windowCoordinator.documentOpen.openFileRequest(FileOpenRequest(
                            fileURLs: selectedFileURLs,
                            origin: .folderWatchInitialBatchAutoOpen,
                            folderWatchSession: request.session,
                            slotStrategy: .reuseEmptySlotForFirst,
                            materializationStrategy: .deferThenMaterializeSelected
                        ))
                    }
                )
            }
            .sheet(isPresented: $coordinator.isTitlebarEditingFavorites) {
                EditFavoritesSheet(
                    favorites: settingsStore.currentSettings.favoriteWatchedFolders,
                    onAction: { action in
                        windowCoordinator.contentActions.handle(action)
                    }
                )
            }
            .sheet(isPresented: $coordinator.isEditingSubfolders) {
                if let session = folderWatchFlowController.sharedFolderWatchSession {
                    EditFolderWatchSheet(
                        folderURL: session.folderURL,
                        currentExcludedSubdirectoryPaths: session.options.excludedSubdirectoryPaths,
                        onConfirm: { newExclusions in
                            if windowCoordinator.folderWatchSession.updateExclusions(newExclusions) {
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
                    windowCoordinator.events.handleWindowAccessorUpdate(window)
                }
            )
            .navigationTitle(windowCoordinator.shell.effectiveWindowTitle)
            .task {
                performInitialSetupIfNeeded()
            }
            .onOpenURL { url in
                windowCoordinator.documentOpen.openIncomingURL(url)
            }
            .onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
                windowCoordinator.shell.applyTitlePresentation()
                windowCoordinator.appearanceLock.renderSelectedDocumentIfNeeded()
            }
            .onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
                windowCoordinator.sidebarMetrics.handleVisibilityChange(oldCount: oldCount, newCount: newCount)
            }
            .onChange(of: sidebarDocumentController.selectedWindowTitle) { _, _ in
                windowCoordinator.shell.applyTitlePresentation()
            }
            .onChange(of: sidebarDocumentController.selectedHasUnacknowledgedExternalChange) { _, _ in
                windowCoordinator.shell.applyTitlePresentation()
            }
            .onChange(of: folderWatchFlowController.sharedFolderWatchSession) { _, _ in
                windowCoordinator.shell.refreshRegistrationAndTitle()
                favoriteWorkspaceController.syncOpenDocumentsIfNeeded()
            }
            .onChange(of: windowCoordinator.events.openDocumentPathTracker.openDocumentPaths) { _, _ in
                favoriteWorkspaceController.syncOpenDocumentsIfNeeded()
            }
    }

    private func windowLifecycleChangeObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning) { _, warning in
                windowCoordinator.folderWatchSession.handleAutoOpenWarningChange(warning)
            }
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession) { _, _ in
                windowCoordinator.refreshWindowShellState()
            }
            .onChange(of: folderWatchFlowController.isFolderWatchOptionsPresented) { _, isPresented in
                if !isPresented {
                    windowCoordinator.folderWatchSession.refreshAutoOpenWarningPresentation()
                }
            }
            .onChange(of: groupStateController.persistenceSnapshot) { oldSnapshot, newSnapshot in
                windowCoordinator.events.handleGroupStateChange(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)
            }
            .onChange(of: sidebarDocumentController.documents.map(\.id)) { _, _ in
                windowCoordinator.events.handleDocumentListChange()
            }
            .onAppear {
                windowCoordinator.events.handleWindowAppear()
            }
            .onDisappear {
                windowCoordinator.events.handleWindowDisappear()
            }
            .onChange(of: appearanceController.effectiveAppearance) { _, _ in
                windowCoordinator.appearanceLock.reapplyAcrossOpenDocuments()
            }
            .onChange(of: favoriteWorkspaceController.activeFavoriteWorkspaceState) { _, newState in
                windowCoordinator.events.handleFavoriteWorkspaceStateChange(newState)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window === windowCoordinator.shell.hostWindow else {
                    return
                }
                windowCoordinator.refreshWindowPresentation()
                windowCoordinator.folderWatchSession.refreshAutoOpenWarningPresentation()
            }
    }

    private func performInitialSetupIfNeeded() {
        guard !windowCoordinator.hasOpenedInitialFile else { return }
        windowCoordinator.hasOpenedInitialFile = true
        uiTestLaunchCoordinator.configure(actions: UITestLaunchCoordinator.Actions(
            hostWindow: { [weak windowCoordinator] in windowCoordinator?.shell.hostWindow },
            startWatchingFolder: { [weak windowCoordinator] folderURL, options in
                windowCoordinator?.folderWatchSession.startWatchingFolder(folderURL: folderURL, options: options)
            },
            presentFolderWatchOptions: { [weak folderWatchFlowController] folderURL, options in
                folderWatchFlowController?.presentOptions(for: folderURL, options: options)
            },
            openFileRequest: { [weak windowCoordinator] request in
                windowCoordinator?.documentOpen.openFileRequest(request)
            },
            isSessionActive: { [weak folderWatchFlowController] in
                folderWatchFlowController?.sharedFolderWatchSession != nil
            }
        ))
        recentHistoryCoordinator.configure(folderWatchFlowController: folderWatchFlowController)
        windowCoordinator.documentOpen.applyInitialSeedIfNeeded(seed: seed)
        folderWatchFlowController.refreshSharedState()
        // Now that all controllers are wired, try to apply the UI-test launch
        // configuration. If the host window isn't attached yet, the window-
        // accessor callback in handleHostWindowChange() will retry.
        uiTestLaunchCoordinator.applyConfigurationIfNeeded()
    }

    private func commandNotificationAwareView<Content: View>(_ view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: CommandNotification.openRecentFile)) { notification in
                recentHistoryCoordinator.handleOpenRecentFileNotification(
                    notification,
                    hostWindowNumber: windowCoordinator.shell.hostWindow?.windowNumber
                ) { fileURL in
                    windowCoordinator.documentOpen.openDocumentInCurrentWindow(fileURL)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CommandNotification.prepareRecentWatchedFolder)) { notification in
                recentHistoryCoordinator.handlePrepareRecentWatchedFolderNotification(
                    notification,
                    hostWindowNumber: windowCoordinator.shell.hostWindow?.windowNumber
                )
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        SidebarWorkspaceView(
            sidebarPlacement: sidebarPlacement,
            sidebarWidth: windowCoordinator.sidebarMetrics.width,
            onSidebarWidthChanged: { newWidth in
                windowCoordinator.sidebarMetrics.handleWidthChange(newWidth)
            },
            detail: { store in
                contentView(for: store)
            },
            actions: SidebarSelectionActions(
                openInDefaultApp: { documentIDs in
                    windowCoordinator.sidebarActions.openDocumentsInDefaultApp(documentIDs)
                },
                openInApplication: { application, documentIDs in
                    windowCoordinator.sidebarActions.openDocumentsInApplication(application, documentIDs)
                },
                revealInFinder: { documentIDs in
                    windowCoordinator.sidebarActions.revealDocumentsInFinder(documentIDs)
                },
                stopWatchingFolders: { documentIDs in
                    windowCoordinator.sidebarActions.stopWatchingFolders(documentIDs)
                },
                closeDocuments: { documentIDs in
                    windowCoordinator.sidebarActions.closeSelectedDocuments(documentIDs)
                },
                closeOtherDocuments: { documentIDs in
                    windowCoordinator.sidebarActions.closeOtherDocuments(keeping: documentIDs)
                },
                closeAll: {
                    windowCoordinator.sidebarActions.closeAllDocuments()
                }
            )
        )
    }

    private func contentView(for store: DocumentStore) -> some View {
        ContentViewAdapter(
            documentStore: store,
            onAction: { action in
                windowCoordinator.contentActions.handle(action)
            }
        )
    }

    private func promptForFolderWatch() {
        guard let folderURL = MarkdownOpenPanel.pickFolder(
            title: "Start Watching a Folder",
            message: "MarkdownObserver will auto-open Markdown files in this folder and keep the preview in sync as files change. You'll confirm what to open in the next step.",
            prompt: "Choose Folder"
        ) else { return }
        folderWatchFlowController.prepareOptions(for: folderURL)
    }
}
