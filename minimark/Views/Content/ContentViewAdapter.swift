import SwiftUI

/// Narrows the `@Observable` observation scope for `ContentView`: reads from the sidebar
/// controller, settings store, and appearance controller are tracked only for this view's
/// body, not for the root or sidebar workspace view.
struct ContentViewAdapter: View {
    let documentStore: DocumentStore
    let sidebarDocumentController: SidebarDocumentController
    let settingsStore: SettingsStore
    let appearanceController: WindowAppearanceController

    let sharedFolderWatchSession: FolderWatchSession?
    let canStopSharedFolderWatch: Bool
    let pendingFolderWatchURL: URL?

    let onAction: (ContentViewAction) -> Void

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: FolderWatchOpenMode
    @Binding var pendingFolderWatchScope: FolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    var body: some View {
        let favorites = settingsStore.currentSettings.favoriteWatchedFolders
        let isCurrentWatchAFavorite: Bool = {
            guard let session = sharedFolderWatchSession else { return false }
            let normalizedPath = FileRouting.normalizedFileURL(session.folderURL).path
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

        ContentAreaHost(
            documentStore: documentStore,
            settingsStore: settingsStore,
            folderWatchState: folderWatchState,
            onAction: onAction,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
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

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: FolderWatchOpenMode
    @Binding var pendingFolderWatchScope: FolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    @State private var viewModel: ContentAreaViewModel

    init(
        documentStore: DocumentStore,
        settingsStore: SettingsStore,
        folderWatchState: ContentViewFolderWatchState,
        onAction: @escaping (ContentViewAction) -> Void,
        isFolderWatchOptionsPresented: Binding<Bool>,
        pendingFolderWatchOpenMode: Binding<FolderWatchOpenMode>,
        pendingFolderWatchScope: Binding<FolderWatchScope>,
        pendingFolderWatchExcludedSubdirectoryPaths: Binding<[String]>
    ) {
        self.documentStore = documentStore
        self.settingsStore = settingsStore
        self.folderWatchState = folderWatchState
        self.onAction = onAction
        self._isFolderWatchOptionsPresented = isFolderWatchOptionsPresented
        self._pendingFolderWatchOpenMode = pendingFolderWatchOpenMode
        self._pendingFolderWatchScope = pendingFolderWatchScope
        self._pendingFolderWatchExcludedSubdirectoryPaths = pendingFolderWatchExcludedSubdirectoryPaths
        _viewModel = State(wrappedValue: ContentAreaViewModel(
            document: documentStore.document,
            rendering: documentStore.renderingController,
            sourceEditing: documentStore.sourceEditingController,
            externalChange: documentStore.externalChange,
            toc: documentStore.toc,
            settingsStore: settingsStore,
            folderWatchState: folderWatchState,
            surfaceViewModel: DocumentSurfaceViewModel(),
            onAction: onAction
        ))
    }

    var body: some View {
        viewModel.applyHostInputs(folderWatchState: folderWatchState, onAction: onAction)
        return ContentView(
            viewModel: viewModel,
            toc: documentStore.toc,
            document: documentStore.document,
            rendering: documentStore.renderingController,
            sourceEditing: documentStore.sourceEditingController,
            settingsStore: settingsStore,
            surfaceViewModel: viewModel.surfaceViewModel,
            folderWatchState: folderWatchState,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
        )
    }
}
