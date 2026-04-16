import Foundation
import Observation

@MainActor
@Observable
final class FavoriteWorkspaceController {
    private let settingsStore: any ReaderSettingsReading & ReaderFavoriteWriting

    // Cross-references (set via configure())
    private weak var sidebarDocumentController: ReaderSidebarDocumentController?
    private weak var folderWatchFlowController: FolderWatchFlowController?
    private weak var groupStateController: SidebarGroupStateController?
    private weak var appearanceController: WindowAppearanceController?

    private(set) var activeFavoriteID: UUID?
    private(set) var activeFavoriteWorkspaceState: ReaderFavoriteWorkspaceState?

    var isActive: Bool { activeFavoriteID != nil }

    init(settingsStore: some ReaderSettingsReading & ReaderFavoriteWriting) {
        self.settingsStore = settingsStore
    }

    func configure(
        sidebarDocumentController: ReaderSidebarDocumentController,
        folderWatchFlowController: FolderWatchFlowController,
        groupStateController: SidebarGroupStateController,
        appearanceController: WindowAppearanceController
    ) {
        self.sidebarDocumentController = sidebarDocumentController
        self.folderWatchFlowController = folderWatchFlowController
        self.groupStateController = groupStateController
        self.appearanceController = appearanceController
    }

    // MARK: - State Mutations

    func activate(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
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

    func updateSidebarPosition(_ position: ReaderMultiFileDisplayMode) {
        activeFavoriteWorkspaceState?.sidebarPosition = position
    }

    func updateLockedAppearance(_ appearance: LockedAppearance?) {
        activeFavoriteWorkspaceState?.lockedAppearance = appearance
    }

    func updateGroupState(
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        groupSortMode: ReaderSidebarSortMode,
        fileSortMode: ReaderSidebarSortMode,
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
        options: ReaderFolderWatchOptions,
        in favorites: [ReaderFavoriteWatchedFolder]
    ) -> ReaderFavoriteWatchedFolder? {
        let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path
        return favorites.first { $0.matches(folderPath: normalizedPath, options: options) }
    }

    func matchingCurrentSession() -> ReaderFavoriteWatchedFolder? {
        guard let session = folderWatchFlowController?.sharedFolderWatchSession else { return nil }
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
        sidebarDocumentController?.documents.compactMap { $0.readerStore.document.fileURL } ?? []
    }

    // MARK: - Persistence

    func persistFinalState(to settingsStore: some ReaderFavoriteWriting) {
        guard let id = activeFavoriteID, let state = activeFavoriteWorkspaceState else { return }
        settingsStore.updateFavoriteWorkspaceState(id: id, workspaceState: state)
    }

    func persistFinalStateIfNeeded() {
        persistFinalState(to: settingsStore)
    }

    // MARK: - Favorite Lifecycle

    func saveAsFavorite(name: String, currentSidebarWidth: CGFloat) {
        guard let session = folderWatchFlowController?.sharedFolderWatchSession,
              let groupStateController else { return }
        let groupSnapshot = groupStateController.persistenceSnapshot
        var workspaceState = ReaderFavoriteWorkspaceState.from(
            settings: settingsStore.currentSettings,
            pinnedGroupIDs: groupSnapshot.pinnedGroupIDs,
            collapsedGroupIDs: groupSnapshot.collapsedGroupIDs,
            sidebarWidth: currentSidebarWidth
        )
        workspaceState.fileSortMode = groupSnapshot.fileSortMode
        workspaceState.groupSortMode = groupSnapshot.sortMode
        workspaceState.lockedAppearance = appearanceController?.lockedAppearance
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
    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) -> CGFloat {
        // Restore appearance FIRST
        if let lockedAppearance = entry.workspaceState.lockedAppearance {
            appearanceController?.restore(from: lockedAppearance)
        } else if appearanceController?.isLocked == true {
            appearanceController?.unlock()
        }

        // Activate and restore workspace state
        activate(id: entry.id, workspaceState: entry.workspaceState)
        groupStateController?.applyWorkspaceState(entry.workspaceState)

        // Start watching folder (via FWFC)
        let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry)
        folderWatchFlowController?.startWatchingFolder(
            folderURL: resolvedURL,
            options: entry.options,
            performInitialAutoOpen: false
        )

        // Open restored files
        let restoredFileURLs = entry.existingOpenDocumentFileURLs(relativeTo: resolvedURL)
        if let session = folderWatchFlowController?.sharedFolderWatchSession,
           let fileOpenCoordinator = sidebarDocumentController?.fileOpenCoordinator,
           !restoredFileURLs.isEmpty {
            fileOpenCoordinator.open(FileOpenRequest(
                fileURLs: restoredFileURLs,
                origin: .folderWatchInitialBatchAutoOpen,
                folderWatchSession: session,
                slotStrategy: .reuseEmptySlotForFirst,
                materializationStrategy: .deferThenMaterializeNewest(
                    count: ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
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
        guard let session = folderWatchFlowController?.sharedFolderWatchSession,
              let favorite = matchingCurrentSession() else { return }

        settingsStore.updateFavoriteWatchedFolderOpenDocuments(
            id: favorite.id,
            folderURL: session.folderURL,
            openDocumentFileURLs: openDocumentFileURLs()
        )
    }

    func clearAll() {
        settingsStore.clearFavoriteWatchedFolders()
    }

    // MARK: - Private

    private func discoverNewFilesForFavorite(
        _ entry: ReaderFavoriteWatchedFolder,
        resolvedFolderURL: URL
    ) {
        sidebarDocumentController?.folderWatchCoordinator.scanCurrentMarkdownFiles { [weak self] scannedURLs in
            guard let self,
                  let session = folderWatchFlowController?.sharedFolderWatchSession,
                  let fileOpenCoordinator = sidebarDocumentController?.fileOpenCoordinator else {
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
                sidebarDocumentController?.selectDocumentWithNewestModificationDate()
            }

            settingsStore.updateFavoriteWatchedFolderKnownDocuments(
                id: entry.id,
                folderURL: resolvedFolderURL,
                knownDocumentFileURLs: scannedURLs
            )
        }
    }
}
