import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    let viewModel: ContentAreaViewModel

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: FolderWatchOpenMode
    @Binding var pendingFolderWatchScope: FolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    var body: some View {
        baseBody.modifier(ContentViewFocusedValues(
            document: viewModel.document,
            sourceEditing: viewModel.sourceEditing,
            toc: viewModel.toc,
            folderWatchState: viewModel.folderWatchState,
            onAction: viewModel.onAction,
            canNavigateChangedRegions: viewModel.canNavigateChangedRegions,
            onNavigateChangedRegion: viewModel.requestChangeNavigation,
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
        ))
    }

    private var baseBody: some View {
        ZStack(alignment: .top) {
            mainStack
            topBar
        }
        .overlay(alignment: .bottomLeading) {
            ContentViewUITestAccessibilityLabel(
                isEnabled: viewModel.isUITestModeEnabled,
                makeValue: { viewModel.previewAccessibilityValue }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var mainStack: some View {
        VStack(spacing: 0) {
            ContentStatusBanner(
                isCurrentFileMissing: viewModel.document.isCurrentFileMissing,
                fileDisplayName: viewModel.document.fileDisplayName,
                errorMessage: viewModel.document.lastError?.message,
                needsImageDirectoryAccess: viewModel.rendering.needsImageDirectoryAccess,
                topPadding: viewModel.overlayLayout.statusBannerTopPadding,
                onGrantImageAccess: viewModel.promptForImageDirectoryAccess
            )
            documentSurfaceWithOverlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ContentDropModifier(
            isBlockedFolderDropTargeted: viewModel.surfaceViewModel.dropTargeting.isBlockedFolderDropTargeted,
            isDragTargeted: viewModel.surfaceViewModel.dropTargeting.isDragTargeted
        ))
        .modifier(ContentViewObservers(viewModel: viewModel))
        .onAppear { viewModel.handleAppear() }
    }

    private var topBar: some View {
        ReaderTopBar(
            document: viewModel.document,
            sourceEditing: viewModel.sourceEditing,
            statusBarTimestamp: viewModel.statusBarTimestamp,
            canStopFolderWatch: viewModel.folderWatchState.canStopFolderWatch,
            apps: viewModel.document.openInApplications,
            favoriteWatchedFolders: viewModel.folderWatchState.favoriteWatchedFolders,
            recentWatchedFolders: viewModel.folderWatchState.recentWatchedFolders,
            recentManuallyOpenedFiles: viewModel.folderWatchState.recentManuallyOpenedFiles,
            iconProvider: appIconImage(for:),
            onAction: viewModel.dispatchTopBarAction
        )
        .environment(\.colorScheme, viewModel.overlayColorScheme)
    }

    private var documentSurfaceWithOverlays: some View {
        documentSurfaceLayout
            .overlay(alignment: .topTrailing) { utilityRail }
            .overlayPreferenceValue(TOCButtonAnchorKey.self) { anchor in
                if viewModel.toc.isVisible, let anchor {
                    TOCOverlayView(
                        headings: viewModel.toc.headings,
                        buttonAnchor: anchor,
                        colorScheme: viewModel.overlayColorScheme,
                        onDismiss: { viewModel.toc.isVisible = false },
                        onSelectHeading: { viewModel.toc.scrollTo($0) }
                    )
                }
            }
            .overlay(alignment: .topLeading) { changeNavigationOverlay }
            .animation(.easeOut(duration: 0.25), value: viewModel.canNavigateChangedRegions)
            .overlay(alignment: .top) { watchPillOverlay }
            .animation(.easeOut(duration: 0.25), value: viewModel.folderWatchState.activeFolderWatch != nil)
    }

    private var utilityRail: some View {
        ContentUtilityRailView(
            state: ContentUtilityRailState(
                hasFile: viewModel.document.fileURL != nil,
                documentViewMode: viewModel.sourceEditing.documentViewMode,
                showEditButton: viewModel.showSourceEditingControls && !viewModel.sourceEditing.isSourceEditing,
                canStartSourceEditing: viewModel.document.hasOpenDocument
                    && !viewModel.document.isCurrentFileMissing
                    && !viewModel.sourceEditing.isSourceEditing,
                hasTOCHeadings: !viewModel.toc.headings.isEmpty
            ),
            isTOCVisible: Binding(
                get: { viewModel.toc.isVisible },
                set: { viewModel.toc.isVisible = $0 }
            ),
            onSetDocumentViewMode: { mode in
                viewModel.sourceEditing.setViewMode(mode, hasOpenDocument: viewModel.document.hasOpenDocument)
            },
            onStartSourceEditing: { viewModel.onAction(.startSourceEditing) }
        )
        .padding(.top, viewModel.overlayLayout.insets.railTopPadding)
        .environment(\.colorScheme, viewModel.overlayColorScheme)
    }

    private var changeNavigationOverlay: some View {
        ChangeNavigationOverlayView(
            state: ChangeNavigationState(
                canNavigate: viewModel.canNavigateChangedRegions,
                currentIndex: viewModel.surfaceViewModel.changeNavigation.currentIndex,
                totalCount: viewModel.document.changedRegions.count
            ),
            insets: viewModel.overlayLayout.insets,
            colorScheme: viewModel.overlayColorScheme,
            settingsStore: viewModel.settingsStore,
            onNavigate: viewModel.requestChangeNavigation
        )
    }

    private var watchPillOverlay: some View {
        WatchPillOverlayView(
            state: WatchPillState(
                activeFolderWatch: viewModel.folderWatchState.activeFolderWatch,
                isCurrentWatchAFavorite: viewModel.folderWatchState.isCurrentWatchAFavorite,
                canStop: viewModel.folderWatchState.canStopFolderWatch,
                isAppearanceLocked: viewModel.folderWatchState.isAppearanceLocked
            ),
            insets: viewModel.overlayLayout.insets,
            hasChangeNavigation: viewModel.canNavigateChangedRegions,
            colorScheme: viewModel.overlayColorScheme,
            onAction: viewModel.dispatchWatchPillAction
        )
    }

    private var documentSurfaceLayout: some View {
        DocumentSurfaceLayoutView(
            documentViewMode: viewModel.sourceEditing.documentViewMode,
            hasOpenDocument: viewModel.document.hasOpenDocument,
            showsLoadingOverlay: viewModel.shouldShowDocumentLoadingOverlay,
            loadingOverlayHeadline: viewModel.loadingOverlayHeadline,
            loadingOverlaySubtitle: viewModel.loadingOverlaySubtitle,
            emptyStateVariant: viewModel.emptyStateVariant,
            currentReaderTheme: viewModel.currentReaderTheme,
            onDroppedFileURLs: viewModel.handleDroppedFileURLs,
            previewSurface: DocumentSurfaceHost(
                configuration: viewModel.makeSurfaceConfiguration(for: .preview),
                fallbackMarkdown: viewModel.document.sourceMarkdown
            ),
            sourceSurface: DocumentSurfaceHost(
                configuration: viewModel.makeSurfaceConfiguration(for: .source),
                fallbackMarkdown: viewModel.document.sourceMarkdown
            )
        )
    }
}

#Preview {
    let settingsStore = ReaderSettingsStore()
    let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
    let securityScopeResolver = SecurityScopeResolver(
        securityScope: SecurityScopedResourceAccess(),
        settingsStore: settingsStore,
        requestWatchedFolderReauthorization: { _ in nil }
    )
    let fileDeps = ReaderFileDependencies(
        watcher: FileChangeWatcher(),
        io: ReaderDocumentIOService(),
        actions: ReaderFileActionService()
    )
    let renderingDeps = ReaderRenderingDependencies(
        renderer: MarkdownRenderingService(),
        differ: ChangedRegionDiffer()
    )
    let document = ReaderDocumentController(
        fileDependencies: fileDeps,
        settingsStore: settingsStore,
        settler: settler
    )
    let rendering = ReaderRenderingController(
        renderingDependencies: renderingDeps,
        settingsStore: settingsStore,
        securityScopeResolver: securityScopeResolver
    )
    let sourceEditing = ReaderSourceEditingController()
    let externalChange = ReaderExternalChangeController()
    let toc = ReaderTOCController()

    let viewModel = ContentAreaViewModel(
        document: document,
        rendering: rendering,
        sourceEditing: sourceEditing,
        externalChange: externalChange,
        toc: toc,
        settingsStore: settingsStore,
        folderWatchState: ContentViewFolderWatchState(
            activeFolderWatch: nil,
            isFolderWatchInitialScanInProgress: false,
            isFolderWatchInitialScanFailed: false,
            canStopFolderWatch: false,
            pendingFolderWatchURL: nil,
            isCurrentWatchAFavorite: false,
            favoriteWatchedFolders: [],
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [],
            isAppearanceLocked: false,
            effectiveReaderTheme: .blackOnWhite
        ),
        surfaceViewModel: DocumentSurfaceViewModel(),
        onAction: { _ in }
    )

    return ContentView(
        viewModel: viewModel,
        isFolderWatchOptionsPresented: .constant(false),
        pendingFolderWatchOpenMode: .constant(.watchChangesOnly),
        pendingFolderWatchScope: .constant(.selectedFolderOnly),
        pendingFolderWatchExcludedSubdirectoryPaths: .constant([])
    )
}
