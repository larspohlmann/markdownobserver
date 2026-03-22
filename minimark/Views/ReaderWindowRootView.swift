import AppKit
import SwiftUI

struct ReaderWindowRootView: View {
    private struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: ReaderFolderWatchOptions
    }

    private enum UITestLaunchAction {
        case none
        case simulateAutoOpenWatchFlow
        case presentWatchFolderSheet(URL)
        case startWatchingFolder(URL)
    }

    let seed: ReaderWindowSeed?
    let settingsStore: ReaderSettingsStore
    let multiFileDisplayMode: ReaderMultiFileDisplayMode

    @Environment(\.openWindow) private var openWindow
    @StateObject private var sidebarDocumentController: ReaderSidebarDocumentController
    @State private var hasOpenedInitialFile = false
    @State private var hostWindow: NSWindow?
    @State private var isFolderWatchOptionsPresented = false
    @State private var pendingFolderWatchRequest: PendingFolderWatchRequest?
    @State private var sharedFolderWatchSession: ReaderFolderWatchSession?
    @State private var canStopSharedFolderWatch = false
    @State private var uiTestWatchFlowTask: Task<Void, Never>?
    @State private var hasAppliedUITestLaunchConfiguration = false
    @State private var effectiveWindowTitle = ReaderWindowTitleFormatter.appName
    @StateObject private var folderWatchOpenCoordinator = ReaderFolderWatchOpenCoordinator()
    @StateObject private var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()

    init(
        seed: ReaderWindowSeed?,
        settingsStore: ReaderSettingsStore,
        multiFileDisplayMode: ReaderMultiFileDisplayMode
    ) {
        self.seed = seed
        self.settingsStore = settingsStore
        self.multiFileDisplayMode = multiFileDisplayMode
        _sidebarDocumentController = StateObject(
            wrappedValue: ReaderSidebarDocumentController(settingsStore: settingsStore)
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
        sidebarDocumentController.setStoreConfigurator { store in
            configureReaderStoreCallbacks(store)
        }
        configureReaderStoreCallbacks(sidebarDocumentController.selectedReaderStore)
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

    private func configureReaderStoreCallbacks(_ store: ReaderStore) {
        store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, folderWatchSession, origin in
            openAdditionalDocument(
                event.fileURL,
                folderWatchSession: folderWatchSession,
                origin: origin,
                initialDiffBaselineMarkdown: event.kind == .modified ? event.previousMarkdown : nil
            )
        }
    }

    private func openIncomingURL(_ url: URL) {
        guard url.isFileURL else {
            return
        }

        guard ReaderFileRouting.isSupportedMarkdownFileURL(url) else {
            return
        }

        openDocumentInSelectedSlot(at: url, origin: .manual)
    }

    private func openDocumentInCurrentWindow(_ fileURL: URL) {
        openDocumentInSelectedSlot(
            at: fileURL,
            origin: .manual,
            folderWatchSession: sharedFolderWatchSession
        )
    }

    private func applyInitialSeedIfNeeded() {
        if let recentOpenedFile = seed?.recentOpenedFile {
            openDocumentInCurrentWindow(recentOpenedFile.resolvedFileURL)
        } else if let fileURL = seed?.fileURL {
            openDocumentInSelectedSlot(
                at: fileURL,
                origin: seed?.openOrigin ?? .manual,
                folderWatchSession: seed?.folderWatchSession,
                initialDiffBaselineMarkdown: seed?.initialDiffBaselineMarkdown
            )
        }

        if let recentWatchedFolder = seed?.recentWatchedFolder {
            prepareRecentFolderWatch(recentWatchedFolder)
        }
    }

    private func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        sidebarDocumentController.openDocumentInSelectedSlot(
            at: fileURL,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        refreshWindowPresentation()
    }

    private func prepareFolderWatchOptions(for folderURL: URL) {
        presentFolderWatchOptions(for: folderURL, options: .default)
    }

    private func presentFolderWatchOptions(for folderURL: URL, options: ReaderFolderWatchOptions) {
        pendingFolderWatchRequest = PendingFolderWatchRequest(
            folderURL: folderURL,
            options: options
        )
        isFolderWatchOptionsPresented = true
    }

    private func prepareRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        presentFolderWatchOptions(for: entry.resolvedFolderURL, options: entry.options)
    }

    private func updatePendingFolderWatchRequest(
        _ update: (inout PendingFolderWatchRequest) -> Void
    ) {
        guard var request = pendingFolderWatchRequest else {
            return
        }

        update(&request)
        pendingFolderWatchRequest = request
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

    private func resolvedUITestLaunchAction() -> UITestLaunchAction {
        let configuration = ReaderUITestLaunchConfiguration.current
        guard configuration.isUITestModeEnabled else {
            return .none
        }

        guard hostWindow != nil else {
            return .none
        }

        if configuration.shouldSimulateAutoOpenWatchFlow {
            return .simulateAutoOpenWatchFlow
        }

        guard let watchFolderURL = configuration.watchFolderURL else {
            return .none
        }

        if configuration.shouldPresentWatchFolderSheet {
            return .presentWatchFolderSheet(watchFolderURL)
        }

        if configuration.shouldAutoStartWatchingFolder {
            return .startWatchingFolder(watchFolderURL)
        }

        return .none
    }

    private func startUITestAutoOpenWatchFlow() {
        let watchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-ui-watch-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: watchFolderURL, withIntermediateDirectories: true)
            startWatchingFolder(folderURL: watchFolderURL, options: .default)

            uiTestWatchFlowTask?.cancel()
            uiTestWatchFlowTask = Task { @MainActor in
                let fileURL = watchFolderURL.appendingPathComponent("auto-open.md")
                await waitForUITestFolderWatchStartup()
                try? "# Auto Open\n\nFirst version\n".write(to: fileURL, atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .milliseconds(1800))
                try? "# Auto Open\n\nLater version\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {}
    }

    private func waitForUITestFolderWatchStartup() async {
        let minimumDelay: Duration = .milliseconds(1200)
        let pollInterval: Duration = .milliseconds(150)
        let startupDeadline = ContinuousClock.now + .seconds(4)

        try? await Task.sleep(for: minimumDelay)

        while sharedFolderWatchSession == nil,
              ContinuousClock.now < startupDeadline {
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func cancelFolderWatch() {
        isFolderWatchOptionsPresented = false
        pendingFolderWatchRequest = nil
    }

    private func confirmFolderWatch(_ options: ReaderFolderWatchOptions) {
        guard let folderURL = pendingFolderWatchRequest?.folderURL else {
            return
        }

        startWatchingFolder(folderURL: folderURL, options: options)
        cancelFolderWatch()
    }

    private func stopFolderWatch() {
        dismissFolderWatchAutoOpenWarning()

        sidebarDocumentController.stopFolderWatch()
        refreshWindowPresentation()
        cancelFolderWatch()
    }

    private func handleFolderWatchAutoOpenWarningChange(_ warning: ReaderFolderWatchAutoOpenWarning?) {
        folderWatchWarningCoordinator.handleWarningChange(warning) {
            isFolderWatchWarningPresentationAllowed()
        }
    }

    private func refreshFolderWatchAutoOpenWarningPresentation() {
        let warning = sidebarDocumentController.selectedFolderWatchAutoOpenWarning
        handleFolderWatchAutoOpenWarningChange(warning)
    }

    private func dismissFolderWatchAutoOpenWarning() {
        folderWatchWarningCoordinator.dismiss {
            sidebarDocumentController.dismissFolderWatchAutoOpenWarnings()
        }
    }

    private func openSelectedFolderWatchAutoOpenFiles() {
        let selectedFileURLs = folderWatchWarningCoordinator.selectedFileURLs()
        guard !selectedFileURLs.isEmpty else {
            dismissFolderWatchAutoOpenWarning()
            return
        }

        dismissFolderWatchAutoOpenWarning()
        openSidebarDocumentsBurst(at: selectedFileURLs, preferEmptySelection: false)
    }

    private func isFolderWatchWarningPresentationAllowed() -> Bool {
        let targetWindow = hostWindow ?? NSApp.keyWindow
        return !isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }

    private func openAdditionalDocument(
        _ fileURL: URL,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        origin: ReaderOpenOrigin = .manual,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)

        if ReaderWindowRegistry.shared.focusDocumentIfAlreadyOpen(at: normalizedFileURL) {
            return
        }

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

        sidebarDocumentController.openAdditionalDocument(
            at: normalizedFileURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        refreshWindowPresentation()
    }

    private func startRecentFolderWatch(_ entry: ReaderRecentWatchedFolder) {
        prepareRecentFolderWatch(entry)
    }

    private func clearRecentWatchedFolders() {
        settingsStore.clearRecentWatchedFolders()
    }

    private func clearRecentManuallyOpenedFiles() {
        settingsStore.clearRecentManuallyOpenedFiles()
    }

    private func notificationTargetsCurrentWindow(_ notification: Notification) -> Bool {
        guard let hostWindow else {
            return false
        }

        guard let requestedWindowNumber = notification.userInfo?[ReaderCommandNotification.targetWindowNumberKey] as? Int else {
            return false
        }

        return hostWindow.windowNumber == requestedWindowNumber
    }

    private func applyWindowTitlePresentation() {
        let resolvedTitle = ReaderWindowTitleFormatter.resolveWindowTitle(
            documentTitle: sidebarDocumentController.selectedWindowTitle,
            activeFolderWatch: sharedFolderWatchSession,
            hasUnacknowledgedExternalChange: sidebarDocumentController.selectedHasUnacknowledgedExternalChange
        )
        effectiveWindowTitle = resolvedTitle
        hostWindow?.title = resolvedTitle
    }

    private func enqueueFolderWatchOpen(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin
    ) {
        folderWatchOpenCoordinator.enqueue(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin
        ) { [self] in
            flushQueuedFolderWatchOpens()
        }
    }

    private func folderWatchChangeEvent(
        for fileURL: URL,
        initialDiffBaselineMarkdown: String?
    ) -> ReaderFolderWatchChangeEvent {
        ReaderFolderWatchChangeEvent(
            fileURL: fileURL,
            kind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            previousMarkdown: initialDiffBaselineMarkdown
        )
    }

    private func flushQueuedFolderWatchOpens() {
        let batch = folderWatchOpenCoordinator.consumeBatchIfPossible(
            canFlushImmediately: hostWindow != nil
        ) { [self] in
            flushQueuedFolderWatchOpens()
        }

        guard let batch else {
            return
        }

        openSidebarDocumentsBurst(
            at: batch.fileURLs,
            origin: batch.openOrigin,
            folderWatchSession: batch.folderWatchSession,
            initialDiffBaselineMarkdownByURL: batch.initialDiffBaselineMarkdownByURL,
            preferEmptySelection: true
        )
    }

    private func openSidebarDocumentsBurst(
        at fileURLs: [URL],
        origin: ReaderOpenOrigin = .manual,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdownByURL: [URL: String] = [:],
        preferEmptySelection: Bool
    ) {
        guard !fileURLs.isEmpty else {
            return
        }

        sidebarDocumentController.openDocumentsBurst(
            at: fileURLs,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdownByURL,
            preferEmptySelection: preferEmptySelection
        )
        refreshWindowPresentation()
    }

    private func refreshSharedFolderWatchState() {
        sharedFolderWatchSession = sidebarDocumentController.activeFolderWatchSession
        canStopSharedFolderWatch = sidebarDocumentController.canStopFolderWatch
    }

    private func refreshWindowPresentation() {
        refreshSharedFolderWatchState()
        applyWindowTitlePresentation()
    }

    private func refreshWindowShellRegistrationAndTitle() {
        registerWindowIfNeeded()
        applyWindowTitlePresentation()
    }

    private func refreshWindowShellState() {
        registerWindowIfNeeded()
        refreshWindowPresentation()
    }

    private func handleHostWindowStateChange() {
        refreshWindowShellState()
        applyUITestLaunchConfigurationIfNeeded()

        guard hostWindow != nil,
              folderWatchOpenCoordinator.hasPendingEvents else {
            return
        }

        flushQueuedFolderWatchOpens()
    }

    private func startWatchingFolder(folderURL: URL, options: ReaderFolderWatchOptions) {
        do {
            try sidebarDocumentController.startWatchingFolder(folderURL: folderURL, options: options)
        } catch {
            sidebarDocumentController.selectedReaderStore.presentError(error)
        }

        refreshWindowPresentation()
    }

    private func performSidebarMutation(_ mutation: () -> Void) {
        mutation()
        refreshWindowPresentation()
    }

    private func closeSidebarDocument(_ documentID: UUID) {
        performSidebarMutation {
            sidebarDocumentController.closeDocument(documentID)
        }
    }

    private func openSidebarDocumentsInDefaultApp(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(nil, documentIDs: documentIDs)
    }

    private func openSidebarDocumentsInApplication(_ application: ReaderExternalApplication, _ documentIDs: Set<UUID>) {
        sidebarDocumentController.openDocumentsInApplication(application, documentIDs: documentIDs)
    }

    private func revealSidebarDocumentsInFinder(_ documentIDs: Set<UUID>) {
        sidebarDocumentController.revealDocumentsInFinder(documentIDs)
    }

    private func stopWatchingSidebarFolders(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.stopWatchingFolders(documentIDs)
        }
    }

    private func closeOtherSidebarDocuments(keeping documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeOtherDocuments(keeping: documentIDs)
        }
    }

    private func closeSelectedSidebarDocuments(_ documentIDs: Set<UUID>) {
        performSidebarMutation {
            sidebarDocumentController.closeDocuments(documentIDs)
        }
    }

    private func closeAllSidebarDocuments() {
        performSidebarMutation {
            sidebarDocumentController.closeAllDocuments()
        }
    }

    private func toggleSidebarPlacement() {
        settingsStore.updateMultiFileDisplayMode(multiFileDisplayMode.toggledSidebarPlacementMode)
    }

    private func registerWindowIfNeeded() {
        ReaderWindowRegistry.shared.registerWindow(
            hostWindow,
            focusDocument: { fileURL in
                sidebarDocumentController.focusDocument(at: fileURL)
            },
            watchedFolderURLProvider: {
                sharedFolderWatchSession?.folderURL
            }
        )
    }
}
