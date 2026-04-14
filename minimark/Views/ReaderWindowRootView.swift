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
            commandNotificationAwareView(windowLifecycleChangeObservers(windowLifecycleBaseView(rootContent)))
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

    private func windowLifecycleBaseView<Content: View>(_ view: Content) -> some View {
        @Bindable var warningCoord = folderWatchFlowController.warningCoordinator
        @Bindable var folderWatchCoordinator = sidebarDocumentController.folderWatchCoordinator
        @Bindable var coordinator = windowCoordinator
        @Bindable var folderWatchFlow = folderWatchFlowController
        return view
            .sheet(item: $warningCoord.activeFlow, onDismiss: {
                windowCoordinator.dismissFolderWatchAutoOpenWarning()
            }) { flow in
                FolderWatchAutoOpenWarningFlowSheet(
                    flow: flow,
                    onKeepCurrentFiles: {
                        windowCoordinator.dismissFolderWatchAutoOpenWarning()
                    },
                    onOpenSelectedFiles: {
                        windowCoordinator.openSelectedFolderWatchAutoOpenFiles()
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
                        windowCoordinator.openFileRequest(FileOpenRequest(
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
                        windowCoordinator.handleEditFavoritesAction(action)
                    }
                )
            }
            .sheet(isPresented: $coordinator.isEditingSubfolders) {
                if let session = folderWatchFlowController.sharedFolderWatchSession {
                    EditFolderWatchSheet(
                        folderURL: session.folderURL,
                        currentExcludedSubdirectoryPaths: session.options.excludedSubdirectoryPaths,
                        onConfirm: { newExclusions in
                            if windowCoordinator.updateFolderWatchExclusions(newExclusions) {
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
                    windowCoordinator.handleWindowAccessorUpdate(window)
                }
            )
            .navigationTitle(windowCoordinator.effectiveWindowTitle)
            .task {
                performInitialSetupIfNeeded()
            }
            .onOpenURL { url in
                windowCoordinator.openIncomingURL(url)
            }
            .onChange(of: windowCoordinator.hostWindow) { _, _ in
                windowCoordinator.handleHostWindowChange()
            }
            .onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
                windowCoordinator.applyWindowTitlePresentation()
                windowCoordinator.renderSelectedDocumentIfNeeded()
            }
            .onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
                windowCoordinator.handleSidebarVisibilityChange(oldCount: oldCount, newCount: newCount)
            }
            .onChange(of: sidebarDocumentController.selectedWindowTitle) { _, _ in
                windowCoordinator.applyWindowTitlePresentation()
            }
            .onChange(of: sidebarDocumentController.selectedHasUnacknowledgedExternalChange) { _, _ in
                windowCoordinator.applyWindowTitlePresentation()
            }
            .onChange(of: folderWatchFlowController.sharedFolderWatchSession) { _, _ in
                windowCoordinator.refreshWindowShellRegistrationAndTitle()
                windowCoordinator.syncSharedFavoriteOpenDocumentsIfNeeded()
            }
            .onChange(of: windowCoordinator.openDocumentPathTracker.openDocumentPaths) { _, _ in
                windowCoordinator.syncSharedFavoriteOpenDocumentsIfNeeded()
            }
    }

    private func windowLifecycleChangeObservers<Content: View>(_ view: Content) -> some View {
        view
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning) { _, warning in
                windowCoordinator.handleFolderWatchAutoOpenWarningChange(warning)
            }
            .onChange(of: sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession) { _, _ in
                windowCoordinator.refreshWindowShellState()
            }
            .onChange(of: folderWatchFlowController.isFolderWatchOptionsPresented) { _, isPresented in
                if !isPresented {
                    windowCoordinator.refreshFolderWatchAutoOpenWarningPresentation()
                }
            }
            .onChange(of: groupStateController.persistenceSnapshot) { oldSnapshot, newSnapshot in
                windowCoordinator.handleGroupStateChange(oldSnapshot: oldSnapshot, newSnapshot: newSnapshot)
            }
            .onChange(of: sidebarDocumentController.documents.map(\.id)) { _, _ in
                windowCoordinator.handleDocumentListChange()
            }
            .onAppear {
                windowCoordinator.handleWindowAppear()
            }
            .onDisappear {
                windowCoordinator.handleWindowDisappear()
            }
            .onChange(of: appearanceController.effectiveAppearance) { _, _ in
                windowCoordinator.reapplyAppearance()
            }
            .onChange(of: favoriteWorkspaceController.activeFavoriteWorkspaceState) { _, newState in
                windowCoordinator.handleFavoriteWorkspaceStateChange(newState)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                guard let window = notification.object as? NSWindow,
                      window === windowCoordinator.hostWindow else {
                    return
                }
                windowCoordinator.refreshWindowPresentation()
                windowCoordinator.refreshFolderWatchAutoOpenWarningPresentation()
            }
    }

    private func performInitialSetupIfNeeded() {
        guard !windowCoordinator.hasOpenedInitialFile else { return }
        windowCoordinator.hasOpenedInitialFile = true
        windowCoordinator.configure(
            appearanceController: appearanceController,
            groupStateController: groupStateController,
            favoriteWorkspaceController: favoriteWorkspaceController,
            folderWatchFlowController: folderWatchFlowController
        )
        windowCoordinator.applyInitialSeedIfNeeded(seed: seed)
        windowCoordinator.refreshSharedFolderWatchState()
    }

    private func commandNotificationAwareView<Content: View>(_ view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.openRecentFile)) { notification in
                windowCoordinator.handleOpenRecentFileNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.prepareRecentWatchedFolder)) { notification in
                windowCoordinator.handlePrepareRecentWatchedFolderNotification(notification)
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
                windowCoordinator.handleSidebarWidthChange(newWidth)
            },
            detail: { store in
                contentView(for: store)
            },
            onToggleSidebarPlacement: {
                windowCoordinator.toggleSidebarPlacement(currentMultiFileDisplayMode: multiFileDisplayMode)
            },
            onOpenInDefaultApp: { documentIDs in
                windowCoordinator.openSidebarDocumentsInDefaultApp(documentIDs)
            },
            onOpenInApplication: { application, documentIDs in
                windowCoordinator.openSidebarDocumentsInApplication(application, documentIDs)
            },
            onRevealInFinder: { documentIDs in
                windowCoordinator.revealSidebarDocumentsInFinder(documentIDs)
            },
            onStopWatchingFolders: { documentIDs in
                windowCoordinator.stopWatchingSidebarFolders(documentIDs)
            },
            onCloseDocuments: { documentIDs in
                windowCoordinator.closeSelectedSidebarDocuments(documentIDs)
            },
            onCloseOtherDocuments: { documentIDs in
                windowCoordinator.closeOtherSidebarDocuments(keeping: documentIDs)
            },
            onCloseAllDocuments: {
                windowCoordinator.closeAllSidebarDocuments()
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
                        if case .activate = action {
                            promptForFolderWatch()
                        } else {
                            windowCoordinator.handleFolderWatchToolbarAction(action)
                        }
                    },
                    compact: true
                )
                .padding(.trailing, 8)
            }

            ToolbarItem(placement: .primaryAction) {
                if sidebarDocumentController.documents.count > 1 {
                    Button(action: {
                        windowCoordinator.toggleSidebarPlacement(currentMultiFileDisplayMode: multiFileDisplayMode)
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
            onAction: { action in
                windowCoordinator.handleContentViewAction(action)
            },
            isFolderWatchOptionsPresented: $folderWatchFlow.isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenModeBinding,
            pendingFolderWatchScope: pendingFolderWatchScopeBinding,
            pendingFolderWatchExcludedSubdirectoryPaths: pendingFolderWatchExcludedSubdirectoryPathsBinding
        )
    }

    private func promptForFolderWatch() {
        guard let folderURL = MarkdownOpenPanel.pickFolder(
            title: "Choose Folder to Watch",
            message: "Select a folder, then choose watch options."
        ) else { return }
        windowCoordinator.prepareFolderWatchOptions(for: folderURL)
    }
}
