import AppKit
import SwiftUI

struct ReaderWindowRootView: View {
    struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: ReaderFolderWatchOptions
    }

    let seed: ReaderWindowSeed?
    let settingsStore: ReaderSettingsStore
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
        multiFileDisplayMode.sidebarPlacement
    }

    private var pendingFolderWatchURL: URL? {
        pendingFolderWatchRequest?.folderURL
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
                refreshWindowShellState()
            }
            .onChange(of: sidebarDocumentController.selectedWindowTitle) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: sidebarDocumentController.selectedHasUnacknowledgedExternalChange) { _, _ in
                applyWindowTitlePresentation()
            }
            .onChange(of: sharedFolderWatchSession) { _, _ in
                refreshWindowShellRegistrationAndTitle()
            }
            .onChange(of: settingsStore.currentSettings) { _, _ in
                applyWindowTitlePresentation()
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

                openDocumentInCurrentWindow(entry.resolvedFileURL)
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
                openAdditionalDocument(fileURL)
            },
            openDocumentInCurrentWindow: { fileURL in
                openDocumentInCurrentWindow(fileURL)
            },
            activeFolderWatch: sharedFolderWatchSession,
            canStopFolderWatch: canStopSharedFolderWatch,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchURL: pendingFolderWatchURL,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenModeBinding,
            pendingFolderWatchScope: pendingFolderWatchScopeBinding,
            recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
            recentManuallyOpenedFiles: settingsStore.currentSettings.recentManuallyOpenedFiles,
            onRequestFolderWatch: prepareFolderWatchOptions,
            onConfirmFolderWatch: confirmFolderWatch,
            onCancelFolderWatch: cancelFolderWatch,
            onStopFolderWatch: stopFolderWatch,
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
            case .simulateAutoOpenWatchFlow:
                startUITestAutoOpenWatchFlow()
                hasAppliedUITestLaunchConfiguration = true
            case .presentWatchFolderSheet(let watchFolderURL):
                prepareFolderWatchOptions(for: watchFolderURL)
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
