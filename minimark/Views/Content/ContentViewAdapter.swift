import SwiftUI

/// Narrows the `@Observable` observation scope for `ContentView`: reads from the sidebar
/// controller, settings store, folder-watch flow, and appearance controller are tracked
/// only for this view's body, not for the root or sidebar workspace view.
struct ContentViewAdapter: View {
    let documentStore: DocumentStore
    let onAction: (ContentViewAction) -> Void

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(WindowAppearanceController.self) private var appearanceController
    @Environment(SidebarDocumentController.self) private var sidebarDocumentController
    @Environment(FolderWatchFlowController.self) private var folderWatchFlow

    var body: some View {
        let favorites = settingsStore.currentSettings.favoriteWatchedFolders
        let session = folderWatchFlow.sharedFolderWatchSession
        let isCurrentWatchAFavorite: Bool = {
            guard let session else { return false }
            let normalizedPath = FileRouting.normalizedFileURL(session.folderURL).path
            return favorites.contains { $0.matches(folderPath: normalizedPath, options: session.options) }
        }()

        let folderWatchState = ContentViewFolderWatchState(
            activeFolderWatch: session,
            isFolderWatchInitialScanInProgress: sidebarDocumentController.folderWatchCoordinator.isFolderWatchInitialScanInProgress,
            isFolderWatchInitialScanFailed: sidebarDocumentController.folderWatchCoordinator.didFolderWatchInitialScanFail,
            canStopFolderWatch: folderWatchFlow.canStopSharedFolderWatch,
            pendingFolderWatchURL: folderWatchFlow.pendingFolderWatchURL,
            isCurrentWatchAFavorite: isCurrentWatchAFavorite,
            favoriteWatchedFolders: favorites,
            recentWatchedFolders: settingsStore.currentSettings.recentWatchedFolders,
            recentManuallyOpenedFiles: settingsStore.currentSettings.recentManuallyOpenedFiles,
            isAppearanceLocked: appearanceController.isLocked,
            effectiveReaderTheme: appearanceController.effectiveAppearance.readerTheme,
            effectiveReaderThemeOverride: appearanceController.effectiveAppearance.readerThemeOverride
        )

        ContentAreaHost(
            documentStore: documentStore,
            settingsStore: settingsStore,
            folderWatchState: folderWatchState,
            onAction: onAction
        )
        // Remount the host (and its @State viewModel) when the selected
        // DocumentStore changes; otherwise SwiftUI preserves @State across
        // document swaps and the VM keeps the prior store's controllers.
        .id(ObjectIdentifier(documentStore))
    }
}

/// Owns the `ContentAreaViewModel` as `@State` so its observation-tracking wiring survives
/// across host-body re-evaluations. Inputs that change per parent eval (`folderWatchState`,
/// `onAction`) are pushed into the VM via `applyHostInputs` on each body.
private struct ContentAreaHost: View {
    let documentStore: DocumentStore
    let settingsStore: SettingsStore
    let folderWatchState: ContentViewFolderWatchState
    let onAction: (ContentViewAction) -> Void

    @State private var surfaceViewModel: DocumentSurfaceViewModel
    @State private var viewModel: ContentAreaViewModel

    init(
        documentStore: DocumentStore,
        settingsStore: SettingsStore,
        folderWatchState: ContentViewFolderWatchState,
        onAction: @escaping (ContentViewAction) -> Void
    ) {
        self.documentStore = documentStore
        self.settingsStore = settingsStore
        self.folderWatchState = folderWatchState
        self.onAction = onAction
        let surfaceViewModel = DocumentSurfaceViewModel()
        _surfaceViewModel = State(wrappedValue: surfaceViewModel)
        _viewModel = State(wrappedValue: ContentAreaViewModel(
            document: documentStore.document,
            rendering: documentStore.renderingController,
            sourceEditing: documentStore.sourceEditingController,
            externalChange: documentStore.externalChange,
            toc: documentStore.toc,
            settingsStore: settingsStore,
            folderWatchState: folderWatchState,
            surfaceViewModel: surfaceViewModel,
            onAction: onAction
        ))
    }

    var body: some View {
        viewModel.applyHostInputs(folderWatchState: folderWatchState, onAction: onAction)
        return ContentView(
            viewModel: viewModel,
            documentStore: documentStore,
            settingsStore: settingsStore,
            surfaceViewModel: surfaceViewModel,
            folderWatchState: folderWatchState
        )
    }
}
