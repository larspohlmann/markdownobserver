import AppKit
import SwiftUI

struct ReaderWindowRootView: View {
    struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: ReaderFolderWatchOptions
    }

    let seed: ReaderWindowSeed?
    @ObservedObject var settingsStore: ReaderSettingsStore
    let multiFileDisplayMode: ReaderMultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @StateObject var sidebarDocumentController: ReaderSidebarDocumentController
    @State private var hasOpenedInitialFile = false
    @State var hostWindow: NSWindow?
    @State var isFolderWatchOptionsPresented = false
    @State var pendingFolderWatchRequest: PendingFolderWatchRequest?
    @State var sharedFolderWatchSession: ReaderFolderWatchSession?
    @State var canStopSharedFolderWatch = false
    @State private var uiTestWatchFlowTask: Task<Void, Never>?
    @State private var hasAppliedUITestLaunchConfiguration = false
    @State var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    @State var sidebarPinnedGroupIDs: Set<String> = []
    @State var sidebarCollapsedGroupIDs: Set<String> = []
    @State var sidebarWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    @State private var lastAppliedSidebarDelta: CGFloat = 0
    @State var activeFavoriteID: UUID?
    @State var activeFavoriteWorkspaceState: ReaderFavoriteWorkspaceState?
    @StateObject var windowCoordinator: ReaderWindowCoordinator
    @StateObject var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()

    init(
        seed: ReaderWindowSeed?,
        settingsStore: ReaderSettingsStore,
        multiFileDisplayMode: ReaderMultiFileDisplayMode
    ) {
        self.seed = seed
        self.settingsStore = settingsStore
        self.multiFileDisplayMode = multiFileDisplayMode
        let sidebarDocumentController = ReaderSidebarDocumentController(settingsStore: settingsStore)
        _sidebarDocumentController = StateObject(wrappedValue: sidebarDocumentController)
        _windowCoordinator = StateObject(
            wrappedValue: ReaderWindowCoordinator(
                settingsStore: settingsStore,
                sidebarDocumentController: sidebarDocumentController
            )
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

    private var fileSortModeBinding: Binding<ReaderSidebarSortMode> {
        Binding(
            get: {
                activeFavoriteWorkspaceState?.fileSortMode
                    ?? settingsStore.currentSettings.sidebarSortMode
            },
            set: { newValue in
                if activeFavoriteWorkspaceState != nil {
                    activeFavoriteWorkspaceState?.fileSortMode = newValue
                } else {
                    settingsStore.updateSidebarSortMode(newValue)
                }
            }
        )
    }

    private var groupSortModeBinding: Binding<ReaderSidebarSortMode> {
        Binding(
            get: {
                activeFavoriteWorkspaceState?.groupSortMode
                    ?? settingsStore.currentSettings.sidebarGroupSortMode
            },
            set: { newValue in
                if activeFavoriteWorkspaceState != nil {
                    activeFavoriteWorkspaceState?.groupSortMode = newValue
                } else {
                    settingsStore.updateSidebarGroupSortMode(newValue)
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
        view
            .sheet(item: $folderWatchWarningCoordinator.activeFlow, onDismiss: {
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
            .sheet(item: $sidebarDocumentController.pendingFileSelectionRequest, onDismiss: {
                sidebarDocumentController.dismissPendingFileSelectionRequest()
            }) { request in
                FolderWatchFileSelectionSheetWrapper(
                    request: request,
                    onSkip: {
                        sidebarDocumentController.dismissPendingFileSelectionRequest()
                    },
                    onConfirm: { selectedFileURLs in
                        sidebarDocumentController.dismissPendingFileSelectionRequest()
                        openSidebarDocumentsBurst(
                            at: selectedFileURLs,
                            origin: .folderWatchInitialBatchAutoOpen,
                            folderWatchSession: request.session,
                            preferEmptySelection: true
                        )
                    }
                )
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
            }
            .onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
                let isSidebarVisible = newCount > 1
                let wasVisible = oldCount > 1

                guard isSidebarVisible != wasVisible, let window = hostWindow else {
                    return
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
            .onChange(of: sidebarDocumentController.selectedFolderWatchAutoOpenWarning) { _, warning in
                handleFolderWatchAutoOpenWarningChange(warning)
            }
            .onChange(of: sidebarDocumentController.activeFolderWatchSession) { _, _ in
                refreshWindowShellState()
            }
            .onChange(of: isFolderWatchOptionsPresented) { _, isPresented in
                handleFolderWatchOptionsPresentationChange(isPresented)
            }
            .onChange(of: sidebarPinnedGroupIDs) { _, newValue in
                if activeFavoriteWorkspaceState != nil {
                    activeFavoriteWorkspaceState?.pinnedGroupIDs = newValue
                    activeFavoriteWorkspaceState?.sidebarWidth = sidebarWidth
                }
            }
            .onChange(of: sidebarCollapsedGroupIDs) { _, newValue in
                if activeFavoriteWorkspaceState != nil {
                    activeFavoriteWorkspaceState?.collapsedGroupIDs = newValue
                    activeFavoriteWorkspaceState?.sidebarWidth = sidebarWidth
                }
            }
            .onChange(of: activeFavoriteWorkspaceState) { _, newState in
                guard let favoriteID = activeFavoriteID, let state = newState else {
                    return
                }
                settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                handleWindowDidBecomeKey(notification)
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
        windowCoordinator.configureStoreCallbacks { fileURL, folderWatchSession, origin, initialDiffBaselineMarkdown in
            openAdditionalDocument(
                fileURL,
                folderWatchSession: folderWatchSession,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
            )
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
                guard notificationTargetsCurrentWindow(notification) else {
                    return
                }

                guard let entry = notification.userInfo?[ReaderCommandNotification.recentFileEntryKey] as? ReaderRecentOpenedFile else {
                    return
                }

                let resolvedURL = settingsStore.resolvedRecentManuallyOpenedFileURL(matching: entry.fileURL) ?? entry.fileURL
                openDocumentInCurrentWindow(resolvedURL)
            }
            .onReceive(NotificationCenter.default.publisher(for: ReaderCommandNotification.prepareRecentWatchedFolder)) { notification in
                guard notificationTargetsCurrentWindow(notification) else {
                    return
                }

                guard let entry = notification.userInfo?[ReaderCommandNotification.recentWatchedFolderEntryKey] as? ReaderRecentWatchedFolder else {
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
            sidebarPlacement: sidebarPlacement,
            collapsedGroupIDs: $sidebarCollapsedGroupIDs,
            pinnedGroupIDs: $sidebarPinnedGroupIDs,
            fileSortMode: fileSortModeBinding,
            groupSortMode: groupSortModeBinding,
            sidebarWidth: $sidebarWidth,
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
    }

    private func contentView(for store: ReaderStore) -> some View {
        ContentView(
            readerStore: store,
            openAdditionalDocument: { fileURL in
                openAdditionalDocumentInCurrentWindow(fileURL)
            },
            openAdditionalDocumentsInCurrentWindow: { fileURLs in
                openAdditionalDocumentsInCurrentWindow(fileURLs)
            },
            openDocumentInCurrentWindow: { fileURL in
                openDocumentInCurrentWindow(fileURL)
            },
            activeFolderWatch: sharedFolderWatchSession,
            isFolderWatchInitialScanInProgress: sidebarDocumentController.isFolderWatchInitialScanInProgress,
            isFolderWatchInitialScanFailed: sidebarDocumentController.didFolderWatchInitialScanFail,
            canStopFolderWatch: canStopSharedFolderWatch,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchURL: pendingFolderWatchURL,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenModeBinding,
            pendingFolderWatchScope: pendingFolderWatchScopeBinding,
            pendingFolderWatchExcludedSubdirectoryPaths: pendingFolderWatchExcludedSubdirectoryPathsBinding,
            isCurrentWatchAFavorite: isSharedFolderWatchAFavorite,
            favoriteWatchedFolders: settingsStore.currentSettings.favoriteWatchedFolders,
            recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
            recentManuallyOpenedFiles: settingsStore.currentSettings.recentManuallyOpenedFiles,
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
                openDocumentInCurrentWindow(resolvedURL)
            },
            onStartRecentFolderWatch: startRecentFolderWatch,
            onClearRecentWatchedFolders: clearRecentWatchedFolders,
            onClearRecentManuallyOpenedFiles: clearRecentManuallyOpenedFiles
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
            sidebarDocumentController.openDocumentsBurst(
                at: fileURLs,
                origin: .manual
            )
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
