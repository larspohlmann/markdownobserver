import SwiftUI

/// Intermediate view that narrows the `@Observable` observation scope for `ContentView`.
///
/// `ReaderWindowRootView.body` re-evaluates whenever any of its 6+ observed objects change.
/// By moving the `ContentViewFolderWatchState` construction here, the reads from
/// `sidebarDocumentController`, `settingsStore`, and `appearanceController` are tracked
/// only for this view's body — not for the entire root or sidebar workspace view.
struct ContentViewAdapter: View {
    let readerStore: ReaderStore
    let sidebarDocumentController: ReaderSidebarDocumentController
    let settingsStore: ReaderSettingsStore
    let appearanceController: WindowAppearanceController

    let sharedFolderWatchSession: ReaderFolderWatchSession?
    let canStopSharedFolderWatch: Bool
    let pendingFolderWatchURL: URL?

    let callbacks: ContentViewCallbacks

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    var body: some View {
        let favorites = settingsStore.currentSettings.favoriteWatchedFolders
        let isCurrentWatchAFavorite: Bool = {
            guard let session = sharedFolderWatchSession else { return false }
            let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
            return favorites.contains { $0.matches(folderPath: normalizedPath, options: session.options) }
        }()

        ContentView(
            readerStore: readerStore,
            settingsStore: settingsStore,
            folderWatchState: ContentViewFolderWatchState(
                activeFolderWatch: sharedFolderWatchSession,
                isFolderWatchInitialScanInProgress: sidebarDocumentController.folderWatchCoordinator.isFolderWatchInitialScanInProgress,
                isFolderWatchInitialScanFailed: sidebarDocumentController.folderWatchCoordinator.didFolderWatchInitialScanFail,
                canStopFolderWatch: canStopSharedFolderWatch,
                pendingFolderWatchURL: pendingFolderWatchURL,
                isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                favoriteWatchedFolders: favorites,
                recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
                recentManuallyOpenedFiles: settingsStore.currentSettings.recentManuallyOpenedFiles,
                isAppearanceLocked: appearanceController.isLocked,
                effectiveReaderTheme: appearanceController.effectiveAppearance.readerTheme
            ),
            callbacks: callbacks,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
        )
    }
}
