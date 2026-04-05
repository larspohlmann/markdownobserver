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
    let isSharedFolderWatchAFavorite: Bool

    let callbacks: ContentViewCallbacks

    @Binding var isFolderWatchOptionsPresented: Bool
    let pendingFolderWatchOpenMode: Binding<ReaderFolderWatchOpenMode>
    let pendingFolderWatchScope: Binding<ReaderFolderWatchScope>
    let pendingFolderWatchExcludedSubdirectoryPaths: Binding<[String]>

    var body: some View {
        ContentView(
            readerStore: readerStore,
            folderWatchState: ContentViewFolderWatchState(
                activeFolderWatch: sharedFolderWatchSession,
                isFolderWatchInitialScanInProgress: sidebarDocumentController.isFolderWatchInitialScanInProgress,
                isFolderWatchInitialScanFailed: sidebarDocumentController.didFolderWatchInitialScanFail,
                canStopFolderWatch: canStopSharedFolderWatch,
                pendingFolderWatchURL: pendingFolderWatchURL,
                isCurrentWatchAFavorite: isSharedFolderWatchAFavorite,
                favoriteWatchedFolders: settingsStore.currentSettings.favoriteWatchedFolders,
                recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
                recentManuallyOpenedFiles: settingsStore.currentSettings.recentManuallyOpenedFiles,
                isAppearanceLocked: appearanceController.isLocked,
                effectiveReaderTheme: appearanceController.effectiveAppearance.readerTheme
            ),
            callbacks: callbacks,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: pendingFolderWatchOpenMode,
            pendingFolderWatchScope: pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: pendingFolderWatchExcludedSubdirectoryPaths
        )
    }
}
