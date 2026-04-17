import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    let viewModel: ContentAreaViewModel
    @Bindable var toc: TOCController
    let document: DocumentController
    let rendering: RenderingController
    let sourceEditing: SourceEditingController
    let settingsStore: SettingsStore
    let surfaceViewModel: DocumentSurfaceViewModel
    let folderWatchState: ContentViewFolderWatchState

    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: FolderWatchOpenMode
    @Binding var pendingFolderWatchScope: FolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    var body: some View {
        baseBody.modifier(ContentViewFocusedValues(
            document: document,
            sourceEditing: sourceEditing,
            toc: toc,
            folderWatchState: folderWatchState,
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
                isCurrentFileMissing: document.isCurrentFileMissing,
                fileDisplayName: document.fileDisplayName,
                errorMessage: document.lastError?.message,
                needsImageDirectoryAccess: rendering.needsImageDirectoryAccess,
                topPadding: viewModel.overlayLayout.statusBannerTopPadding,
                onGrantImageAccess: viewModel.promptForImageDirectoryAccess
            )
            documentSurfaceWithOverlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ContentDropModifier(
            isBlockedFolderDropTargeted: surfaceViewModel.dropTargeting.isBlockedFolderDropTargeted,
            isDragTargeted: surfaceViewModel.dropTargeting.isDragTargeted
        ))
        .onAppear { viewModel.handleAppear() }
    }

    private var topBar: some View {
        TopBar(
            document: document,
            sourceEditing: sourceEditing,
            statusBarTimestamp: viewModel.statusBarTimestamp,
            canStopFolderWatch: folderWatchState.canStopFolderWatch,
            apps: document.openInApplications,
            favoriteWatchedFolders: folderWatchState.favoriteWatchedFolders,
            recentWatchedFolders: folderWatchState.recentWatchedFolders,
            recentManuallyOpenedFiles: folderWatchState.recentManuallyOpenedFiles,
            iconProvider: appIconImage(for:),
            onAction: viewModel.dispatchTopBarAction
        )
        .environment(\.colorScheme, viewModel.overlayColorScheme)
    }

    private var documentSurfaceWithOverlays: some View {
        documentSurfaceLayout
            .overlay(alignment: .topTrailing) { utilityRail }
            .overlayPreferenceValue(TOCButtonAnchorKey.self) { anchor in
                if toc.isVisible, let anchor {
                    TOCOverlayView(
                        headings: toc.headings,
                        buttonAnchor: anchor,
                        colorScheme: viewModel.overlayColorScheme,
                        onDismiss: { toc.isVisible = false },
                        onSelectHeading: { toc.scrollTo($0) }
                    )
                }
            }
            .overlay(alignment: .topLeading) { changeNavigationOverlay }
            .animation(.easeOut(duration: 0.25), value: viewModel.canNavigateChangedRegions)
            .overlay(alignment: .top) { watchPillOverlay }
            .animation(.easeOut(duration: 0.25), value: folderWatchState.activeFolderWatch != nil)
    }

    private var utilityRail: some View {
        ContentUtilityRailView(
            state: ContentUtilityRailState(
                hasFile: document.fileURL != nil,
                documentViewMode: sourceEditing.documentViewMode,
                showEditButton: viewModel.showSourceEditingControls && !sourceEditing.isSourceEditing,
                canStartSourceEditing: document.hasOpenDocument
                    && !document.isCurrentFileMissing
                    && !sourceEditing.isSourceEditing,
                hasTOCHeadings: !toc.headings.isEmpty
            ),
            isTOCVisible: $toc.isVisible,
            onSetDocumentViewMode: { mode in
                sourceEditing.setViewMode(mode, hasOpenDocument: document.hasOpenDocument)
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
                currentIndex: surfaceViewModel.changeNavigation.currentIndex,
                totalCount: document.changedRegions.count
            ),
            insets: viewModel.overlayLayout.insets,
            colorScheme: viewModel.overlayColorScheme,
            settingsStore: settingsStore,
            onNavigate: viewModel.requestChangeNavigation
        )
    }

    private var watchPillOverlay: some View {
        WatchPillOverlayView(
            state: WatchPillState(
                activeFolderWatch: folderWatchState.activeFolderWatch,
                isCurrentWatchAFavorite: folderWatchState.isCurrentWatchAFavorite,
                canStop: folderWatchState.canStopFolderWatch,
                isAppearanceLocked: folderWatchState.isAppearanceLocked
            ),
            insets: viewModel.overlayLayout.insets,
            hasChangeNavigation: viewModel.canNavigateChangedRegions,
            colorScheme: viewModel.overlayColorScheme,
            onAction: viewModel.dispatchWatchPillAction
        )
    }

    private var documentSurfaceLayout: some View {
        DocumentSurfaceLayoutView(
            documentViewMode: sourceEditing.documentViewMode,
            hasOpenDocument: document.hasOpenDocument,
            showsLoadingOverlay: viewModel.shouldShowDocumentLoadingOverlay,
            loadingOverlayHeadline: viewModel.loadingOverlayHeadline,
            loadingOverlaySubtitle: viewModel.loadingOverlaySubtitle,
            emptyStateVariant: viewModel.emptyStateVariant,
            currentReaderTheme: viewModel.currentReaderTheme,
            onDroppedFileURLs: viewModel.handleDroppedFileURLs,
            previewSurface: DocumentSurfaceHost(
                configuration: viewModel.makeSurfaceConfiguration(for: .preview),
                fallbackMarkdown: document.sourceMarkdown
            ),
            sourceSurface: DocumentSurfaceHost(
                configuration: viewModel.makeSurfaceConfiguration(for: .source),
                fallbackMarkdown: document.sourceMarkdown
            )
        )
    }
}

#Preview {
    let settingsStore = SettingsStore()
    let settler = AutoOpenSettler(settlingInterval: 1.0)
    let securityScopeResolver = SecurityScopeResolver(
        securityScope: SecurityScopedResourceAccess(),
        settingsStore: settingsStore,
        requestWatchedFolderReauthorization: { _ in nil }
    )
    let fileDeps = FileDependencies(
        watcher: FileChangeWatcher(),
        io: DocumentIOService(),
        actions: FileActionService()
    )
    let renderingDeps = RenderingDependencies(
        renderer: MarkdownRenderingService(),
        differ: ChangedRegionDiffer()
    )
    let document = DocumentController(
        fileDependencies: fileDeps,
        settingsStore: settingsStore,
        settler: settler
    )
    let rendering = RenderingController(
        renderingDependencies: renderingDeps,
        settingsStore: settingsStore,
        securityScopeResolver: securityScopeResolver
    )
    let sourceEditing = SourceEditingController()
    let externalChange = ExternalChangeController()
    let toc = TOCController()
    let surfaceViewModel = DocumentSurfaceViewModel()
    let folderWatchState = ContentViewFolderWatchState(
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
    )

    let viewModel = ContentAreaViewModel(
        document: document,
        rendering: rendering,
        sourceEditing: sourceEditing,
        externalChange: externalChange,
        toc: toc,
        settingsStore: settingsStore,
        folderWatchState: folderWatchState,
        surfaceViewModel: surfaceViewModel,
        onAction: { _ in }
    )

    return ContentView(
        viewModel: viewModel,
        toc: toc,
        document: document,
        rendering: rendering,
        sourceEditing: sourceEditing,
        settingsStore: settingsStore,
        surfaceViewModel: surfaceViewModel,
        folderWatchState: folderWatchState,
        isFolderWatchOptionsPresented: .constant(false),
        pendingFolderWatchOpenMode: .constant(.watchChangesOnly),
        pendingFolderWatchScope: .constant(.selectedFolderOnly),
        pendingFolderWatchExcludedSubdirectoryPaths: .constant([])
    )
}
