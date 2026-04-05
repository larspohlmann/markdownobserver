import AppKit
import Foundation

extension ReaderWindowRootView {
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
        guard let session = sharedFolderWatchSession else {
            return
        }
        let groupSnapshot = groupStateController.workspaceStateSnapshot()
        var workspaceState = ReaderFavoriteWorkspaceState.from(
            settings: settingsStore.currentSettings,
            pinnedGroupIDs: groupSnapshot.pinnedGroupIDs,
            collapsedGroupIDs: groupSnapshot.collapsedGroupIDs,
            sidebarWidth: sidebarWidth
        )
        workspaceState.lockedAppearance = appearanceController.lockedAppearance
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
            activeFavoriteID = created.id
            activeFavoriteWorkspaceState = created.workspaceState
        }
    }

    func removeSharedFolderWatchFromFavorites() {
        guard let match = favoriteMatchingSharedFolderWatchSession() else {
            return
        }
        settingsStore.removeFavoriteWatchedFolder(id: match.id)
        activeFavoriteID = nil
        activeFavoriteWorkspaceState = nil
    }

    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
        // Restore appearance FIRST so the controller is in the correct lock state
        // before activeFavoriteWorkspaceState triggers onChange persistence.
        if let lockedAppearance = entry.workspaceState.lockedAppearance {
            appearanceController.restore(from: lockedAppearance)
        } else if appearanceController.isLocked {
            appearanceController.unlock()
        }

        // Set active favorite and restore workspace state
        activeFavoriteID = entry.id
        activeFavoriteWorkspaceState = entry.workspaceState
        groupStateController.applyWorkspaceState(entry.workspaceState)
        sidebarWidth = entry.workspaceState.sidebarWidth

        let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry)
        startWatchingFolder(
            folderURL: resolvedURL,
            options: entry.options,
            performInitialAutoOpen: false
        )

        let restoredFileURLs = entry.resolvedOpenDocumentFileURLs(relativeTo: resolvedURL)
        if let session = sharedFolderWatchSession,
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
        sidebarDocumentController.scanCurrentMarkdownFiles { scannedURLs in
            guard let session = sharedFolderWatchSession else {
                return
            }

            let newFileURLs = entry.newFileURLs(fromScanned: scannedURLs, relativeTo: resolvedFolderURL)
            if !newFileURLs.isEmpty {
                fileOpenCoordinator.open(FileOpenRequest(
                    fileURLs: newFileURLs,
                    origin: .folderWatchInitialBatchAutoOpen,
                    folderWatchSession: session,
                    slotStrategy: .alwaysAppend,
                    materializationStrategy: .deferThenMaterializeSelected
                ))
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
        guard let session = sharedFolderWatchSession,
              let favorite = favoriteMatchingSharedFolderWatchSession() else {
            return
        }

        settingsStore.updateFavoriteWatchedFolderOpenDocuments(
            id: favorite.id,
            folderURL: session.folderURL,
            openDocumentFileURLs: currentSidebarOpenDocumentFileURLs()
        )
    }

    private func favoriteMatchingSharedFolderWatchSession() -> ReaderFavoriteWatchedFolder? {
        guard let session = sharedFolderWatchSession else {
            return nil
        }

        let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
        return settingsStore.currentSettings.favoriteWatchedFolders.first {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
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
        if activeFavoriteID != nil {
            // Only clear if this is NOT being called from startFavoriteWatch
            // (startFavoriteWatch sets activeFavoriteID before calling startWatchingFolder)
            // We can detect this by checking if the folder matches the active favorite
            let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path
            let matchesActiveFavorite = settingsStore.currentSettings.favoriteWatchedFolders.contains {
                $0.id == activeFavoriteID && $0.matches(folderPath: normalizedPath, options: options)
            }
            if !matchesActiveFavorite {
                persistFinalWorkspaceStateIfNeeded()
                activeFavoriteID = nil
                activeFavoriteWorkspaceState = nil
                groupStateController.pinnedGroupIDs = []
                groupStateController.collapsedGroupIDs = []
                sidebarWidth = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
                Task { @MainActor [appearanceController] in
                    if appearanceController.isLocked {
                        appearanceController.unlock()
                    }
                }
            }
        }

        do {
            try sidebarDocumentController.startWatchingFolder(
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
            sidebarDocumentController.stopWatchingFolders(documentIDs)
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

    func toggleSidebarPlacement() {
        if let current = activeFavoriteWorkspaceState?.sidebarPosition {
            activeFavoriteWorkspaceState?.sidebarPosition = current.toggledSidebarPlacementMode
            activeFavoriteWorkspaceState?.sidebarWidth = sidebarWidth
        } else {
            settingsStore.updateMultiFileDisplayMode(multiFileDisplayMode.toggledSidebarPlacementMode)
        }
    }

    func persistFinalWorkspaceStateIfNeeded() {
        guard let favoriteID = activeFavoriteID, let state = activeFavoriteWorkspaceState else {
            return
        }
        settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
    }
}
