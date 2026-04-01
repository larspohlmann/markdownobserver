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

        sidebarDocumentController.openAdditionalDocument(
            at: normalizedFileURL,
            origin: origin,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        applyWindowTitlePresentation()
    }

    func openAdditionalDocumentsInCurrentWindow(
        _ fileURLs: [URL],
        origin: ReaderOpenOrigin = .manual,
        preferEmptySelection: Bool = true
    ) {
        openSidebarDocumentsBurst(
            at: fileURLs,
            origin: origin,
            preferEmptySelection: preferEmptySelection
        )
    }

    var isSharedFolderWatchAFavorite: Bool {
        favoriteMatchingSharedFolderWatchSession() != nil
    }

    func saveSharedFolderWatchAsFavorite(name: String) {
        guard let session = sharedFolderWatchSession else {
            return
        }
        let workspaceState = ReaderFavoriteWorkspaceState.from(
            settings: settingsStore.currentSettings,
            pinnedGroupIDs: sidebarPinnedGroupIDs,
            collapsedGroupIDs: sidebarCollapsedGroupIDs,
            sidebarWidth: sidebarWidth
        )
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
        // Set active favorite and restore workspace state
        activeFavoriteID = entry.id
        activeFavoriteWorkspaceState = entry.workspaceState
        sidebarPinnedGroupIDs = entry.workspaceState.pinnedGroupIDs
        sidebarCollapsedGroupIDs = entry.workspaceState.collapsedGroupIDs
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
            openSidebarDocumentsBurst(
                at: restoredFileURLs,
                origin: .folderWatchInitialBatchAutoOpen,
                folderWatchSession: session,
                preferEmptySelection: true
            )
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
                openSidebarDocumentsBurst(
                    at: newFileURLs,
                    origin: .folderWatchInitialBatchAutoOpen,
                    folderWatchSession: session,
                    preferEmptySelection: false
                )
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

    func notificationTargetsCurrentWindow(_ notification: Notification) -> Bool {
        guard let hostWindow else {
            return false
        }

        guard let requestedWindowNumber = notification.userInfo?[ReaderCommandNotification.targetWindowNumberKey] as? Int else {
            return false
        }

        return hostWindow.windowNumber == requestedWindowNumber
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
                activeFavoriteID = nil
                activeFavoriteWorkspaceState = nil
                sidebarPinnedGroupIDs = []
                sidebarCollapsedGroupIDs = []
                sidebarWidth = ReaderFavoriteWorkspaceState.defaultSidebarWidth
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
        } else {
            settingsStore.updateMultiFileDisplayMode(multiFileDisplayMode.toggledSidebarPlacementMode)
        }
    }
}
