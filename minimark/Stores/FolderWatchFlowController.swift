// minimark/Stores/FolderWatchFlowController.swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class FolderWatchFlowController {
    struct PendingFolderWatchRequest {
        let folderURL: URL
        var options: FolderWatchOptions
    }

    // Presentation state
    var isFolderWatchOptionsPresented = false
    var pendingFolderWatchRequest: PendingFolderWatchRequest?
    var sharedFolderWatchSession: FolderWatchSession?
    var canStopSharedFolderWatch = false
    var warningCoordinator = FolderWatchAutoOpenWarningCoordinator()

    var pendingFolderWatchURL: URL? {
        pendingFolderWatchRequest?.folderURL
    }

    private let settingsStore: SettingsStore
    private let sidebarDocumentController: SidebarDocumentController

    // Cross-references (injected as providers to resolve construction-order cycles).
    private let favoriteWorkspaceControllerProvider: @MainActor () -> FavoriteWorkspaceController?
    private let groupStateControllerProvider: @MainActor () -> SidebarGroupStateController?
    private let appearanceControllerProvider: @MainActor () -> WindowAppearanceController?

    init(
        settingsStore: SettingsStore,
        sidebarDocumentController: SidebarDocumentController,
        favoriteWorkspaceControllerProvider: @escaping @MainActor () -> FavoriteWorkspaceController?,
        groupStateControllerProvider: @escaping @MainActor () -> SidebarGroupStateController?,
        appearanceControllerProvider: @escaping @MainActor () -> WindowAppearanceController?
    ) {
        self.settingsStore = settingsStore
        self.sidebarDocumentController = sidebarDocumentController
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.groupStateControllerProvider = groupStateControllerProvider
        self.appearanceControllerProvider = appearanceControllerProvider
    }

    // MARK: - Presentation State

    func presentOptions(for folderURL: URL, options: FolderWatchOptions) {
        pendingFolderWatchRequest = PendingFolderWatchRequest(
            folderURL: folderURL,
            options: options
        )
        isFolderWatchOptionsPresented = true
    }

    func prepareOptions(for folderURL: URL) {
        presentOptions(for: folderURL, options: .default)
    }

    func prepareRecentWatch(_ entry: RecentWatchedFolder) {
        let resolvedFolderURL = settingsStore.resolvedRecentWatchedFolderURL(matching: entry.folderURL) ?? entry.folderURL
        presentOptions(for: resolvedFolderURL, options: entry.options)
    }

    func cancelPendingWatch() {
        isFolderWatchOptionsPresented = false
        pendingFolderWatchRequest = nil
    }

    func updatePendingRequest(_ update: (inout PendingFolderWatchRequest) -> Void) {
        guard var request = pendingFolderWatchRequest else { return }
        update(&request)
        pendingFolderWatchRequest = request
    }

    // MARK: - Shared State Sync

    func refreshSharedState() {
        sharedFolderWatchSession = sidebarDocumentController.folderWatchCoordinator.activeFolderWatchSession
        canStopSharedFolderWatch = sidebarDocumentController.folderWatchCoordinator.canStopFolderWatch
    }

    // MARK: - Warning Flow

    func handleAutoOpenWarningChange(
        _ warning: FolderWatchAutoOpenWarning?,
        canPresent: @escaping @MainActor () -> Bool
    ) {
        warningCoordinator.handleWarningChange(warning, canPresent: canPresent)
    }

    func refreshAutoOpenWarningPresentation(canPresent: @escaping @MainActor () -> Bool) {
        let warning = sidebarDocumentController.folderWatchCoordinator.selectedFolderWatchAutoOpenWarning
        handleAutoOpenWarningChange(warning, canPresent: canPresent)
    }

    func dismissAutoOpenWarning() {
        warningCoordinator.dismiss {
            sidebarDocumentController.folderWatchCoordinator.dismissFolderWatchAutoOpenWarnings()
        }
    }

    func openSelectedAutoOpenFilesAndRefresh() {
        let selectedFileURLs = warningCoordinator.selectedFileURLs()
        guard !selectedFileURLs.isEmpty else {
            dismissAutoOpenWarning()
            return
        }
        dismissAutoOpenWarning()
        sidebarDocumentController.fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: selectedFileURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))
    }

    func handleAutoOpenWarningChangeForWindow(
        _ warning: FolderWatchAutoOpenWarning?,
        hostWindow: NSWindow?
    ) {
        handleAutoOpenWarningChange(warning) { self.isWarningPresentationAllowed(hostWindow: hostWindow) }
    }

    func refreshAutoOpenWarningPresentationForWindow(hostWindow: NSWindow?) {
        refreshAutoOpenWarningPresentation { self.isWarningPresentationAllowed(hostWindow: hostWindow) }
    }

    // MARK: - Folder Watch Lifecycle

    /// Starts watching a folder, optionally deactivating the current favorite.
    /// Returns `true` if a favorite was deactivated (so the caller can reset sidebar width).
    @discardableResult
    func startWatchingFolder(
        folderURL: URL,
        options: FolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) -> Bool {
        var didDeactivateFavorite = false

        if favoriteWorkspaceControllerProvider()?.activeFavoriteID != nil {
            let normalizedPath = FileRouting.normalizedFileURL(folderURL).path
            let matchesActiveFavorite = settingsStore.currentSettings.favoriteWatchedFolders.contains {
                $0.id == favoriteWorkspaceControllerProvider()?.activeFavoriteID && $0.matches(folderPath: normalizedPath, options: options)
            }
            if !matchesActiveFavorite {
                favoriteWorkspaceControllerProvider()?.persistFinalState(to: settingsStore)
                favoriteWorkspaceControllerProvider()?.deactivate()
                groupStateControllerProvider()?.pinnedGroupIDs = []
                groupStateControllerProvider()?.collapsedGroupIDs = []
                didDeactivateFavorite = true
                Task { @MainActor [appearanceController = appearanceControllerProvider()] in
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
            sidebarDocumentController.selectedDocumentStore.document.handle(error)
        }

        return didDeactivateFavorite
    }

    /// Stops the folder watch session and cleans up associated state.
    /// Does NOT reset `sidebarWidth` or call `refreshWindowPresentation()` — the caller handles those.
    func stopFolderWatchSession() {
        dismissAutoOpenWarning()
        favoriteWorkspaceControllerProvider()?.persistFinalState(to: settingsStore)
        favoriteWorkspaceControllerProvider()?.deactivate()
        groupStateControllerProvider()?.pinnedGroupIDs = []
        groupStateControllerProvider()?.collapsedGroupIDs = []
        sidebarDocumentController.folderWatchCoordinator.stopFolderWatch()
        cancelPendingWatch()
    }

    /// Confirms a pending folder watch request and starts watching.
    /// Returns `true` if a favorite was deactivated.
    @discardableResult
    func confirmFolderWatch(_ options: FolderWatchOptions) -> Bool {
        guard let folderURL = pendingFolderWatchRequest?.folderURL else {
            return false
        }

        let deactivated = startWatchingFolder(folderURL: folderURL, options: options)
        cancelPendingWatch()
        return deactivated
    }

    /// Updates folder watch exclusions, closing/opening documents as needed.
    /// Returns `true` on success.
    @discardableResult
    func updateFolderWatchExclusions(_ newExcludedPaths: [String]) -> Bool {
        guard let session = sharedFolderWatchSession else { return false }

        let normalizedOld = Set(
            session.options.encodedForFolder(session.folderURL).excludedSubdirectoryPaths
        )
        let normalizedNew = Set(
            FolderWatchOptions(
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
            sidebarDocumentController.selectedDocumentStore.document.handle(error)
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

        return true
    }

    private func syncFavoriteExclusionsIfNeeded(_ excludedPaths: [String]) {
        guard let favoriteID = favoriteWorkspaceControllerProvider()?.activeFavoriteID else { return }
        settingsStore.updateFavoriteWatchedFolderExclusions(
            id: favoriteID,
            excludedSubdirectoryPaths: excludedPaths
        )
    }

    // MARK: - Exclusions

    func closeDocumentsInExcludedPaths(_ excludedPaths: [String]) {
        let excludedPrefixes = excludedPaths.map { path in
            let normalized = FileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        let wasSelectedExcluded = sidebarDocumentController.selectedDocument.flatMap { doc in
            doc.documentStore.document.fileURL.map { url in
                let normalized = FileRouting.normalizedFileURL(url).path
                return excludedPrefixes.contains { normalized.hasPrefix($0) }
            }
        } ?? false

        let documentsToClose = sidebarDocumentController.documents.filter { doc in
            guard let fileURL = doc.documentStore.document.fileURL else { return false }
            let normalized = FileRouting.normalizedFileURL(fileURL).path
            return excludedPrefixes.contains { normalized.hasPrefix($0) }
        }

        for doc in documentsToClose {
            sidebarDocumentController.closeDocument(doc.id)
        }

        if wasSelectedExcluded {
            sidebarDocumentController.selectDocumentWithNewestModificationDate()
        }
    }

    func openFilesInNewlyIncludedPaths(
        _ includedPaths: [String]
    ) {
        let fileOpenCoordinator = sidebarDocumentController.fileOpenCoordinator
        let includedPrefixes = includedPaths.map { path in
            let normalized = FileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            return normalized.hasSuffix("/") ? normalized : normalized + "/"
        }

        sidebarDocumentController.folderWatchCoordinator.scanCurrentMarkdownFiles { [self] scannedURLs in
            guard let session = sharedFolderWatchSession else { return }

            let alreadyOpenPaths = Set(
                sidebarDocumentController.documents.compactMap {
                    $0.documentStore.document.fileURL.map { FileRouting.normalizedFileURL($0).path }
                }
            )

            let newFileURLs = scannedURLs.filter { url in
                let normalized = FileRouting.normalizedFileURL(url).path
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
            }
        }
    }

    // MARK: - Helpers

    func isWarningPresentationAllowed(hostWindow: NSWindow?) -> Bool {
        let targetWindow = hostWindow ?? NSApp.keyWindow
        return !isFolderWatchOptionsPresented && targetWindow?.attachedSheet == nil
    }
}
