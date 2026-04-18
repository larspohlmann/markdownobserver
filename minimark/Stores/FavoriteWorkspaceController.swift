import Foundation
import Observation

@MainActor
@Observable
final class FavoriteWorkspaceController {
    private let settingsStore: any SettingsReading & FavoriteWriting

    // Cross-references (injected as providers to resolve construction-order cycles).
    private let sidebarDocumentControllerProvider: @MainActor () -> SidebarDocumentController?
    private let folderWatchFlowControllerProvider: @MainActor () -> FolderWatchFlowController?
    private let groupStateControllerProvider: @MainActor () -> SidebarGroupStateController?
    private let appearanceControllerProvider: @MainActor () -> WindowAppearanceController?

    private(set) var activeFavoriteID: UUID?
    private(set) var activeFavoriteWorkspaceState: FavoriteWorkspaceState?

    var isActive: Bool { activeFavoriteID != nil }

    init(
        settingsStore: some SettingsReading & FavoriteWriting,
        sidebarDocumentControllerProvider: @escaping @MainActor () -> SidebarDocumentController?,
        folderWatchFlowControllerProvider: @escaping @MainActor () -> FolderWatchFlowController?,
        groupStateControllerProvider: @escaping @MainActor () -> SidebarGroupStateController?,
        appearanceControllerProvider: @escaping @MainActor () -> WindowAppearanceController?
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentControllerProvider = sidebarDocumentControllerProvider
        self.folderWatchFlowControllerProvider = folderWatchFlowControllerProvider
        self.groupStateControllerProvider = groupStateControllerProvider
        self.appearanceControllerProvider = appearanceControllerProvider
    }

    // MARK: - State Mutations

    func activate(id: UUID, workspaceState: FavoriteWorkspaceState) {
        activeFavoriteID = id
        activeFavoriteWorkspaceState = workspaceState
    }

    func deactivate() {
        activeFavoriteID = nil
        activeFavoriteWorkspaceState = nil
    }

    func updateSidebarWidth(_ width: CGFloat) {
        activeFavoriteWorkspaceState?.sidebarWidth = width
    }

    func updateSidebarPosition(_ position: MultiFileDisplayMode) {
        activeFavoriteWorkspaceState?.sidebarPosition = position
    }

    func updateLockedAppearance(_ appearance: LockedAppearance?) {
        activeFavoriteWorkspaceState?.lockedAppearance = appearance
    }

    func updateGroupState(
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        groupSortMode: SidebarSortMode,
        fileSortMode: SidebarSortMode,
        manualGroupOrder: [String]?
    ) {
        activeFavoriteWorkspaceState?.pinnedGroupIDs = pinnedGroupIDs
        activeFavoriteWorkspaceState?.collapsedGroupIDs = collapsedGroupIDs
        activeFavoriteWorkspaceState?.groupSortMode = groupSortMode
        activeFavoriteWorkspaceState?.fileSortMode = fileSortMode
        activeFavoriteWorkspaceState?.manualGroupOrder = manualGroupOrder
    }

    // MARK: - Matching

    func matchingFavorite(
        folderURL: URL,
        options: FolderWatchOptions,
        in favorites: [FavoriteWatchedFolder]
    ) -> FavoriteWatchedFolder? {
        let normalizedPath = FileRouting.normalizedFileURL(folderURL).path
        return favorites.first { $0.matches(folderPath: normalizedPath, options: options) }
    }

    func matchingCurrentSession() -> FavoriteWatchedFolder? {
        guard let session = folderWatchFlowControllerProvider()?.sharedFolderWatchSession else { return nil }
        return matchingFavorite(
            folderURL: session.folderURL,
            options: session.options,
            in: settingsStore.currentSettings.favoriteWatchedFolders
        )
    }

    var isCurrentWatchAFavorite: Bool {
        matchingCurrentSession() != nil
    }

    // MARK: - Open Document URLs

    func openDocumentFileURLs() -> [URL] {
        sidebarDocumentControllerProvider()?.documents.compactMap { $0.documentStore.document.fileURL } ?? []
    }

    // MARK: - Persistence

    func persistFinalState(to settingsStore: some FavoriteWriting) {
        guard let id = activeFavoriteID, let state = activeFavoriteWorkspaceState else { return }
        settingsStore.updateFavoriteWorkspaceState(id: id, workspaceState: state)
    }

    func persistFinalStateIfNeeded() {
        persistFinalState(to: settingsStore)
    }

    // MARK: - Favorite Lifecycle

    func saveAsFavorite(name: String, currentSidebarWidth: CGFloat) {
        guard let session = folderWatchFlowControllerProvider()?.sharedFolderWatchSession,
              let groupStateController = groupStateControllerProvider() else { return }
        let groupSnapshot = groupStateController.persistenceSnapshot
        var workspaceState = FavoriteWorkspaceState.from(
            settings: settingsStore.currentSettings,
            pinnedGroupIDs: groupSnapshot.pinnedGroupIDs,
            collapsedGroupIDs: groupSnapshot.collapsedGroupIDs,
            sidebarWidth: currentSidebarWidth
        )
        workspaceState.fileSortMode = groupSnapshot.fileSortMode
        workspaceState.groupSortMode = groupSnapshot.sortMode
        workspaceState.lockedAppearance = appearanceControllerProvider()?.lockedAppearance
        workspaceState.manualGroupOrder = groupSnapshot.manualGroupOrder
        settingsStore.addFavoriteWatchedFolder(
            name: name,
            folderURL: session.folderURL,
            options: session.options,
            openDocumentFileURLs: openDocumentFileURLs(),
            workspaceState: workspaceState
        )

        if let created = matchingCurrentSession() {
            activate(id: created.id, workspaceState: created.workspaceState)
        }
    }

    func removeFromFavorites() {
        guard let match = matchingCurrentSession() else { return }
        settingsStore.removeFavoriteWatchedFolder(id: match.id)
        deactivate()
    }

    /// Returns the sidebar width from the favorite's workspace state (so the caller can apply it to window state).
    func startFavoriteWatch(_ entry: FavoriteWatchedFolder) -> CGFloat {
        // Restore appearance FIRST
        if let lockedAppearance = entry.workspaceState.lockedAppearance {
            appearanceControllerProvider()?.restore(from: lockedAppearance)
        } else if appearanceControllerProvider()?.isLocked == true {
            appearanceControllerProvider()?.unlock()
        }

        // Activate and restore workspace state
        activate(id: entry.id, workspaceState: entry.workspaceState)
        groupStateControllerProvider()?.applyWorkspaceState(entry.workspaceState)

        // Start watching folder (via FWFC)
        let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry)
        folderWatchFlowControllerProvider()?.startWatchingFolder(
            folderURL: resolvedURL,
            options: entry.options,
            performInitialAutoOpen: false
        )
        // Refresh shared state so sharedFolderWatchSession is available
        // for file opening and document sync below.
        folderWatchFlowControllerProvider()?.refreshSharedState()

        // Open restored files
        let restoredFileURLs = entry.existingOpenDocumentFileURLs(relativeTo: resolvedURL)
        if let session = folderWatchFlowControllerProvider()?.sharedFolderWatchSession,
           let fileOpenCoordinator = sidebarDocumentControllerProvider()?.fileOpenCoordinator,
           !restoredFileURLs.isEmpty {
            fileOpenCoordinator.open(FileOpenRequest(
                fileURLs: restoredFileURLs,
                origin: .folderWatchInitialBatchAutoOpen,
                folderWatchSession: session,
                slotStrategy: .reuseEmptySlotForFirst,
                materializationStrategy: .deferThenMaterializeNewest(
                    count: FolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
                )
            ))
        }

        // Sync and discover
        syncOpenDocumentsIfNeeded()

        if entry.options.openMode == .openAllMarkdownFiles {
            discoverNewFilesForFavorite(entry, resolvedFolderURL: resolvedURL)
        }

        return entry.workspaceState.sidebarWidth
    }

    func syncOpenDocumentsIfNeeded() {
        guard let session = folderWatchFlowControllerProvider()?.sharedFolderWatchSession,
              let favorite = matchingCurrentSession() else { return }

        let currentURLs = openDocumentFileURLs()
        // Don't overwrite saved documents with an empty list — this can happen
        // when the sync fires (via .onChange) before restored files are opened.
        guard !currentURLs.isEmpty || favorite.openDocumentRelativePaths.isEmpty else { return }

        settingsStore.updateFavoriteWatchedFolderOpenDocuments(
            id: favorite.id,
            folderURL: session.folderURL,
            openDocumentFileURLs: currentURLs
        )
    }

    func clearAll() {
        settingsStore.clearFavoriteWatchedFolders()
    }

    // MARK: - Private

    private func discoverNewFilesForFavorite(
        _ entry: FavoriteWatchedFolder,
        resolvedFolderURL: URL
    ) {
        sidebarDocumentControllerProvider()?.folderWatchCoordinator.scanCurrentMarkdownFiles { [weak self] scannedURLs in
            guard let self,
                  let session = folderWatchFlowControllerProvider()?.sharedFolderWatchSession,
                  let fileOpenCoordinator = sidebarDocumentControllerProvider()?.fileOpenCoordinator else {
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
                sidebarDocumentControllerProvider()?.selectDocumentWithNewestModificationDate()
            }

            settingsStore.updateFavoriteWatchedFolderKnownDocuments(
                id: entry.id,
                folderURL: resolvedFolderURL,
                knownDocumentFileURLs: scannedURLs
            )
        }
    }
}
