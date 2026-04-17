import AppKit
import Foundation
import SwiftUI

struct ContentView: View {
    let viewModel: ContentAreaViewModel
    let documentStore: DocumentStore
    let settingsStore: SettingsStore
    let surfaceViewModel: DocumentSurfaceViewModel
    let folderWatchState: ContentViewFolderWatchState

    private var toc: TOCController { documentStore.toc }
    private var document: DocumentController { documentStore.document }
    private var rendering: RenderingController { documentStore.renderingController }
    private var sourceEditing: SourceEditingController { documentStore.sourceEditingController }

    var body: some View {
        @Bindable var toc = toc
        return baseBody.modifier(ContentViewFocusedValues(
            documentStore: documentStore,
            folderWatchState: folderWatchState,
            onAction: viewModel.onAction,
            changedRegionNavigation: ChangedRegionNavigationAction(
                canNavigate: viewModel.canNavigateChangedRegions,
                navigate: viewModel.requestChangeNavigation
            )
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
            documentStore: documentStore,
            statusBarTimestamp: viewModel.statusBarTimestamp,
            folderWatchState: folderWatchState,
            apps: document.openInApplications,
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
        @Bindable var toc = toc
        return ContentUtilityRailView(
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
    let securityScopeResolver = SecurityScopeResolver(
        securityScope: SecurityScopedResourceAccess(),
        settingsStore: settingsStore,
        requestWatchedFolderReauthorization: { _ in nil }
    )
    let documentStore = DocumentStore(
        rendering: RenderingDependencies(
            renderer: MarkdownRenderingService(),
            differ: ChangedRegionDiffer()
        ),
        file: FileDependencies(
            watcher: FileChangeWatcher(),
            io: DocumentIOService(),
            actions: FileActionService()
        ),
        folderWatch: FolderWatchDependencies(
            autoOpenPlanner: FolderWatchAutoOpenPlanner(),
            settler: AutoOpenSettler(settlingInterval: 1.0),
            systemNotifier: SystemNotifier.shared
        ),
        settingsStore: settingsStore,
        securityScopeResolver: securityScopeResolver
    )
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
        document: documentStore.document,
        rendering: documentStore.renderingController,
        sourceEditing: documentStore.sourceEditingController,
        externalChange: documentStore.externalChange,
        toc: documentStore.toc,
        settingsStore: settingsStore,
        folderWatchState: folderWatchState,
        surfaceViewModel: surfaceViewModel,
        onAction: { _ in }
    )

    let sidebarDocumentController = SidebarDocumentController(settingsStore: settingsStore)
    let appearanceController = WindowAppearanceController(settingsStore: settingsStore)
    let folderWatchFlow = FolderWatchFlowController(
        settingsStore: settingsStore,
        sidebarDocumentController: sidebarDocumentController
    )

    return ContentView(
        viewModel: viewModel,
        documentStore: documentStore,
        settingsStore: settingsStore,
        surfaceViewModel: surfaceViewModel,
        folderWatchState: folderWatchState
    )
    .environment(settingsStore)
    .environment(appearanceController)
    .environment(sidebarDocumentController)
    .environment(folderWatchFlow)
}
