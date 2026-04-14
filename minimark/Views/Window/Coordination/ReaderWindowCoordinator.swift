import AppKit
import Foundation
import Observation

@MainActor
private struct ReaderWindowStoreCallbackConfigurator {
    let lockedAppearanceProvider: @MainActor () -> LockedAppearance?
    let onOpenAdditionalDocument: (URL, ReaderFolderWatchSession?, ReaderOpenOrigin, String?) -> Void

    func configure(_ store: ReaderStore) {
        if let lockedAppearance = lockedAppearanceProvider() {
            store.setAppearanceOverride(lockedAppearance)
        }
        store.setOpenAdditionalDocumentForFolderWatchEventHandler { event, folderWatchSession, origin in
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
        registerWindowIfNeeded()
        refreshWindowPresentation()
    }

    func registerWindowIfNeeded() {
        registerWindow(
            hostWindow,
            activeFolderWatch: folderWatchFlowController?.sharedFolderWatchSession
        )
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

        // Track this as the active favorite
        let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
        if let created = settingsStore.currentSettings.favoriteWatchedFolders.first(where: {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }) {
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
        sidebarDocumentController.documents.compactMap { $0.readerStore.fileURL }
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
            closeDocumentsInExcludedPaths(Array(newlyExcludedPaths))
        }

        let newlyIncludedPaths = normalizedOld.subtracting(normalizedNew)
        if !newlyIncludedPaths.isEmpty, session.options.openMode == .openAllMarkdownFiles {
            openFilesInNewlyIncludedPaths(Array(newlyIncludedPaths))
        }

        refreshWindowPresentation()
        return true
    }

    private func closeDocumentsInExcludedPaths(_ excludedPaths: [String]) {
        let excludedPrefixes = excludedPaths.map { path in
            let normalized = ReaderFileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        let wasSelectedExcluded = sidebarDocumentController.selectedDocument.flatMap { doc in
            doc.readerStore.fileURL.map { url in
                let normalized = ReaderFileRouting.normalizedFileURL(url).path
                return excludedPrefixes.contains { normalized.hasPrefix($0) }
            }
        } ?? false

        let documentsToClose = sidebarDocumentController.documents.filter { doc in
            guard let fileURL = doc.readerStore.fileURL else { return false }
            let normalized = ReaderFileRouting.normalizedFileURL(fileURL).path
            return excludedPrefixes.contains { normalized.hasPrefix($0) }
        }

        for doc in documentsToClose {
            sidebarDocumentController.closeDocument(doc.id)
        }

        if wasSelectedExcluded {
            sidebarDocumentController.selectDocumentWithNewestModificationDate()
        }
    }

    private func openFilesInNewlyIncludedPaths(_ includedPaths: [String]) {
        let includedPrefixes = includedPaths.map { path in
            let normalized = ReaderFileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        sidebarDocumentController.folderWatchCoordinator.scanCurrentMarkdownFiles { [weak self] scannedURLs in
            guard let self,
                  let session = folderWatchFlowController?.sharedFolderWatchSession else { return }

            let alreadyOpenPaths = Set(
                sidebarDocumentController.documents.compactMap {
                    $0.readerStore.fileURL.map { ReaderFileRouting.normalizedFileURL($0).path }
                }
            )

            let newFileURLs = scannedURLs.filter { url in
                let normalized = ReaderFileRouting.normalizedFileURL(url).path
                guard !alreadyOpenPaths.contains(normalized) else { return false }
                return includedPrefixes.contains { normalized.hasPrefix($0) }
            }

            if !newFileURLs.isEmpty {
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: newFileURLs,
                    origin: .folderWatchInitialBatchAutoOpen,
                    folderWatchSession: session,
                    slotStrategy: .alwaysAppend,
                    materializationStrategy: .deferThenMaterializeNewest(count: 1)
                ))
                refreshWindowPresentation()
            }
        }
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
}
