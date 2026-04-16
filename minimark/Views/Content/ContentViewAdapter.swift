import SwiftUI

/// Narrows the `@Observable` observation scope for `ContentView`: reads from the sidebar
/// controller, settings store, and appearance controller are tracked only for this view's
/// body, not for the root or sidebar workspace view.
struct ContentViewAdapter: View {
    let readerStore: ReaderStore
    let sidebarDocumentController: ReaderSidebarDocumentController
    let settingsStore: ReaderSettingsStore
    let appearanceController: WindowAppearanceController

    let sharedFolderWatchSession: ReaderFolderWatchSession?
    let canStopSharedFolderWatch: Bool
    let pendingFolderWatchURL: URL?

    let onAction: (ContentViewAction) -> Void

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    @State private var surfaceViewModel = DocumentSurfaceViewModel()

    var body: some View {
        let favorites = settingsStore.currentSettings.favoriteWatchedFolders
        let isCurrentWatchAFavorite: Bool = {
            guard let session = sharedFolderWatchSession else { return false }
            let normalizedPath = ReaderFileRouting.normalizedFileURL(session.folderURL).path
            return favorites.contains { $0.matches(folderPath: normalizedPath, options: session.options) }
        }()

        let folderWatchState = ContentViewFolderWatchState(
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
        )

        let viewModel = ContentAreaViewModel(
            document: readerStore.document,
            rendering: readerStore.renderingController,
            sourceEditing: readerStore.sourceEditingController,
            externalChange: readerStore.externalChange,
            toc: readerStore.toc,
            settingsStore: settingsStore,
            folderWatchState: folderWatchState,
            surfaceViewModel: surfaceViewModel,
            onAction: onAction
        )

        ContentView(
            viewModel: viewModel,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
        )
    }
}
