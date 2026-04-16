import AppKit
import Combine
import Foundation
import OSLog
import SwiftUI

struct ContentView: View {
    private enum Metrics {
        static let splitPaneMinimumWidth: CGFloat = 320
    }

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ContentView"
    )

    let document: ReaderDocumentController
    let rendering: ReaderRenderingController
    let sourceEditing: ReaderSourceEditingController
    let externalChange: ReaderExternalChangeController
    let toc: ReaderTOCController
    let settingsStore: ReaderSettingsStore
    let folderWatchState: ContentViewFolderWatchState
    let surfaceViewModel: DocumentSurfaceViewModel
    let onAction: (ContentViewAction) -> Void
    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    // MARK: - Internal: accessible to factory extension in ContentViewConfigurationFactory.swift
    // These properties must be at least `internal` because Swift extensions in separate files
    // cannot see `private` members.

    @StateObject var splitScrollCoordinator = SplitScrollCoordinator()
    @State var dropTargeting = DropTargetingCoordinator()
    @State var previewMode: PreviewMode = .web
    @State var previewReloadToken = 0
    @State var sourceMode: SourceMode = .web
    @State var sourceReloadToken = 0
    @State var changeNavigation = ChangedRegionNavigationCoordinator()
    @State var sourceHTMLCache = SourceHTMLDocumentCache()

    var body: some View {
        baseBody.modifier(ContentViewFocusedValues(
            document: document,
            sourceEditing: sourceEditing,
            toc: toc,
            folderWatchState: folderWatchState,
            onAction: onAction,
            canNavigateChangedRegions: canNavigateChangedRegions,
            onNavigateChangedRegion: { direction in
                changeNavigation.requestNavigation(direction)
                splitScrollCoordinator.suppressPreviewBounceBack()
            },
            isFolderWatchOptionsPresented: $isFolderWatchOptionsPresented,
            pendingFolderWatchOpenMode: $pendingFolderWatchOpenMode,
            pendingFolderWatchScope: $pendingFolderWatchScope,
            pendingFolderWatchExcludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths
        ))
    }

    private var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let date = externalChange.lastExternalChangeAt { return .updated(date) }
        if let date = document.fileLastModifiedAt { return .lastModified(date) }
        if let date = rendering.lastRefreshAt { return .updated(date) }
        return nil
    }

    private var baseBody: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if document.isCurrentFileMissing {
                    DeletedFileWarningBar(
                        fileName: document.fileDisplayName,
                        message: document.lastError?.message
                    )
                    .padding(.top, ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: overlayTopInset))
                } else if rendering.needsImageDirectoryAccess {
                    ImageAccessWarningBar {
                        promptForImageDirectoryAccess()
                    }
                    .padding(.top, ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: overlayTopInset))
                }

                documentSurfaceWithOverlays
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if dropTargeting.isBlockedFolderDropTargeted {
                    FolderDropBlockedOverlayView()
                        .padding(10)
                        .allowsHitTesting(false)
                } else if dropTargeting.isDragTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: document.fileURL?.standardizedFileURL.path) { _, _ in
                handleFileIdentityChange()
            }
            .onChange(of: document.changedRegions) { _, _ in
                changeNavigation.resetForNewRegions()
            }
            .onChange(of: previewMode) { _, newValue in
                handlePreviewModeChange(newValue)
            }
            .onChange(of: sourceMode) { _, newValue in
                handleSourceModeChange(newValue)
            }
            .onChange(of: sourceEditing.documentViewMode) { _, newValue in
                handleDocumentViewModeChange(newValue)
            }
            .onChange(of: sourceEditing.sourceEditorSeedMarkdown) { _, _ in
                refreshSourceHTML()
            }
            .onChange(of: settingsStore.currentSettings) { _, _ in
                refreshSourceHTML()
            }
            .onChange(of: sourceEditing.isSourceEditing) { _, _ in
                refreshSourceHTML()
            }
            .onChange(of: folderWatchState.activeFolderWatch?.folderURL.standardizedFileURL.path) { _, _ in
                dropTargeting.clearAll()
            }
            .onAppear {
                handleSurfaceAppear()
            }

            ReaderTopBar(
                document: document,
                sourceEditing: sourceEditing,
                statusBarTimestamp: statusBarTimestamp,
                canStopFolderWatch: folderWatchState.canStopFolderWatch,
                apps: document.openInApplications,
                favoriteWatchedFolders: folderWatchState.favoriteWatchedFolders,
                recentWatchedFolders: folderWatchState.recentWatchedFolders,
                recentManuallyOpenedFiles: folderWatchState.recentManuallyOpenedFiles,
                iconProvider: appIconImage(for:),
                onAction: { action in
                    switch action {
                    case .openFiles(let urls):
                        handlePickedFileURLs(urls)
                    case .openInApp(let app):
                        onAction(.openInApplication(app))
                    case .revealInFinder:
                        onAction(.revealInFinder)
                    case .saveSourceDraft:
                        onAction(.saveSourceDraft)
                    case .discardSourceDraft:
                        onAction(.discardSourceDraft)
                    case .requestFolderWatch(let url):
                        onAction(.requestFolderWatch(url))
                    case .stopFolderWatch:
                        onAction(.stopFolderWatch)
                    case .startFavoriteWatch(let fav):
                        onAction(.startFavoriteWatch(fav))
                    case .clearFavoriteWatchedFolders:
                        onAction(.clearFavoriteWatchedFolders)
                    case .renameFavoriteWatchedFolder(let id, let name):
                        onAction(.renameFavoriteWatchedFolder(id: id, name: name))
                    case .removeFavoriteWatchedFolder(let id):
                        onAction(.removeFavoriteWatchedFolder(id))
                    case .reorderFavoriteWatchedFolders(let ids):
                        onAction(.reorderFavoriteWatchedFolders(ids))
                    case .startRecentManuallyOpenedFile(let entry):
                        onAction(.startRecentManuallyOpenedFile(entry))
                    case .startRecentFolderWatch(let entry):
                        onAction(.startRecentFolderWatch(entry))
                    case .clearRecentWatchedFolders:
                        onAction(.clearRecentWatchedFolders)
                    case .clearRecentManuallyOpenedFiles:
                        onAction(.clearRecentManuallyOpenedFiles)
                    }
                }
            )
            .environment(\.colorScheme, overlayColorScheme)
        }
        .overlay(alignment: .bottomLeading) {
            if isUITestModeEnabled {
                Text(previewAccessibilityValue)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("reader-preview-summary")
                    .accessibilityLabel("Reader preview summary")
                    .accessibilityValue(previewAccessibilityValue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private func handleFileIdentityChange() {
        changeNavigation.reset()
        if previewMode == .nativeFallback {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback {
            sourceReloadToken += 1
            sourceMode = .web
        }
        dropTargeting.clearAll()
        splitScrollCoordinator.reset()
    }

    private func handlePreviewModeChange(_ mode: PreviewMode) {
        guard mode == .nativeFallback else {
            return
        }

        dropTargeting.clear(for: .preview)
        splitScrollCoordinator.reset()
    }

    private func handleSourceModeChange(_ mode: SourceMode) {
        guard mode == .plainTextFallback else {
            return
        }

        dropTargeting.clear(for: .source)
        splitScrollCoordinator.reset()
    }

    private func handleDocumentViewModeChange(_ mode: ReaderDocumentViewMode) {
        guard mode != .split else {
            return
        }

        splitScrollCoordinator.reset()
    }

    private func handleSurfaceAppear() {
        refreshSourceHTML()

        if previewMode == .nativeFallback, !rendering.renderedHTMLDocument.isEmpty {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback,
           !document.sourceMarkdown.isEmpty {
            sourceReloadToken += 1
            sourceMode = .web
        }
    }

    private func promptForImageDirectoryAccess() {
        guard let directoryURL = document.fileURL?.deletingLastPathComponent() else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Grant Image Access"
        panel.message = "Select the folder containing your images to display them in the preview."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        onAction(.grantImageDirectoryAccess(selectedURL))
    }

    var previewAccessibilityValue: String {
        let fileName = document.fileURL?.lastPathComponent ?? "none"
        return "file=\(fileName)|regions=\(document.changedRegions.count)|mode=\(sourceEditing.documentViewMode.rawValue)|surface=preview"
    }

    var sourceAccessibilityValue: String {
        let fileName = document.fileURL?.lastPathComponent ?? "none"
        return "file=\(fileName)|mode=\(sourceEditing.documentViewMode.rawValue)|surface=source"
    }

    private var documentSurfaceLayout: some View {
        DocumentSurfaceLayoutView(
            documentViewMode: sourceEditing.documentViewMode,
            hasOpenDocument: document.hasOpenDocument,
            showsLoadingOverlay: shouldShowDocumentLoadingOverlay,
            loadingOverlayHeadline: loadingOverlayHeadline,
            loadingOverlaySubtitle: loadingOverlaySubtitle,
            emptyStateVariant: emptyStateVariant,
            currentReaderTheme: currentReaderTheme,
            onDroppedFileURLs: handleDroppedFileURLs,
            previewSurface: documentSurfacePane(for: .preview),
            sourceSurface: documentSurfacePane(for: .source)
        )
    }

    private var overlayColorScheme: ColorScheme {
        currentReaderTheme.kind.isDark ? .dark : .light
    }

    private var overlayTopInset: CGFloat {
        var height = ReaderTopBarMetrics.mainBarHeight
        if sourceEditing.isSourceEditing {
            height += ReaderTopBarMetrics.sourceEditingBarHeight
        }
        return height
    }

    private var isStatusBannerVisible: Bool {
        document.isCurrentFileMissing || rendering.needsImageDirectoryAccess
    }

    var overlayInsets: ReaderOverlayInsetValues {
        ReaderOverlayInsetCalculator.compute(
            topBarInset: overlayTopInset,
            hasStatusBanner: isStatusBannerVisible
        )
    }

    @ViewBuilder
    private var documentSurfaceWithOverlays: some View {
        documentSurfaceLayout
            .overlay(alignment: .topTrailing) {
                contentUtilityRail
                    .padding(.top, overlayInsets.railTopPadding)
                    .environment(\.colorScheme, overlayColorScheme)
            }
            .overlayPreferenceValue(TOCButtonAnchorKey.self) { anchor in
                if toc.isVisible, let anchor {
                    tocOverlay(buttonAnchor: anchor)
                }
            }
            .overlay(alignment: .topLeading) { changeNavigationOverlay }
            .animation(.easeOut(duration: 0.25), value: canNavigateChangedRegions)
            .overlay(alignment: .top) { watchPillOverlay }
            .animation(.easeOut(duration: 0.25), value: folderWatchState.activeFolderWatch != nil)
    }

    @ViewBuilder
    private var changeNavigationOverlay: some View {
        if canNavigateChangedRegions {
            ChangeNavigationPill(
                currentIndex: changeNavigation.currentIndex,
                totalCount: document.changedRegions.count,
                onNavigate: { direction in
                    changeNavigation.requestNavigation(direction)
                    splitScrollCoordinator.suppressPreviewBounceBack()
                }
            )
            .firstUseHint(.changeNavigation, message: "Use the arrows to step through changes", settingsStore: settingsStore)
            .padding(.top, overlayInsets.leadingOverlayTopPadding)
            .padding(.leading, 8)
            .environment(\.colorScheme, overlayColorScheme)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
        }
    }

    @ViewBuilder
    private var watchPillOverlay: some View {
        if let activeWatch = folderWatchState.activeFolderWatch {
            WatchPill(
                activeFolderWatch: activeWatch,
                isCurrentWatchAFavorite: folderWatchState.isCurrentWatchAFavorite,
                canStop: folderWatchState.canStopFolderWatch,
                isAppearanceLocked: folderWatchState.isAppearanceLocked,
                onAction: { action in
                    switch action {
                    case .stop:
                        onAction(.stopFolderWatch)
                    case .saveFavorite(let name):
                        onAction(.saveFolderWatchAsFavorite(name))
                    case .removeFavorite:
                        onAction(.removeCurrentWatchFromFavorites)
                    case .revealInFinder:
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeWatch.folderURL.path)
                    case .toggleAppearanceLock:
                        onAction(.toggleAppearanceLock)
                    case .editSubfolders:
                        onAction(.editSubfolders)
                    }
                }
            )
            .padding(.top, overlayInsets.leadingOverlayTopPadding)
            .padding(.leading, canNavigateChangedRegions ? 150 : 60)
            .padding(.trailing, 70)
            .environment(\.colorScheme, overlayColorScheme)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
        }
    }

    private var contentUtilityRail: some View {
        ContentUtilityRail(
            hasFile: document.fileURL != nil,
            documentViewMode: sourceEditing.documentViewMode,
            showEditButton: showSourceEditingControls && !sourceEditing.isSourceEditing,
            canStartSourceEditing: (document.hasOpenDocument && !document.isCurrentFileMissing && !sourceEditing.isSourceEditing),
            onSetDocumentViewMode: { mode in
                sourceEditing.setViewMode(mode, hasOpenDocument: document.hasOpenDocument)
            },
            onStartSourceEditing: {
                onAction(.startSourceEditing)
            },
            hasTOCHeadings: !toc.headings.isEmpty,
            isTOCVisible: Binding(
                get: { toc.isVisible },
                set: { toc.isVisible = $0 }
            )
        )
    }

    @ViewBuilder
    private func tocOverlay(buttonAnchor: Anchor<CGRect>) -> some View {
        let gap: CGFloat = 8
        let tocColorScheme: ColorScheme = currentReaderTheme.kind.isDark ? .dark : .light

        GeometryReader { proxy in
            let buttonFrame = proxy[buttonAnchor]
            let panelTrailing = buttonFrame.minX - gap

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { toc.isVisible = false }

                TOCPopoverView(
                    headings: toc.headings,
                    onSelect: { heading in
                        toc.scrollTo(heading)
                    }
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                .colorScheme(tocColorScheme)
                .frame(maxWidth: panelTrailing, alignment: .trailing)
                .offset(y: buttonFrame.minY)
            }
        }
    }


    var canNavigateChangedRegions: Bool {
        sourceEditing.documentViewMode != .source &&
            previewMode == .web &&
            !document.changedRegions.isEmpty
    }

    private var showSourceEditingControls: Bool {
        document.hasOpenDocument &&
            (sourceEditing.documentViewMode != .preview || sourceEditing.isSourceEditing)
    }

    var canSynchronizeSplitScroll: Bool {
        sourceEditing.documentViewMode == .split &&
            previewMode == .web &&
            sourceMode == .web
    }

    private var currentReaderTheme: ReaderTheme {
        ReaderTheme.theme(for: folderWatchState.effectiveReaderTheme)
    }

    private var emptyStateVariant: ContentEmptyStateView.Variant {
        if let activeWatch = folderWatchState.activeFolderWatch {
            return .folderWatchEmpty(folderName: activeWatch.detailSummaryTitle)
        }
        return .noDocument
    }

    private var shouldShowDocumentLoadingOverlay: Bool {
        document.documentLoadState == .loading || document.documentLoadState == .settlingAutoOpen
    }

    private var loadingOverlayHeadline: String {
        switch document.documentLoadState {
        case .settlingAutoOpen:
            return "Waiting for file contents\u{2026}"
        case .ready, .loading, .deferred:
            return "Loading document\u{2026}"
        }
    }

    private var loadingOverlaySubtitle: String? {
        switch document.documentLoadState {
        case .settlingAutoOpen:
            return "The new watched document will appear as soon as writing finishes."
        case .ready, .loading, .deferred:
            return nil
        }
    }

    var minimumSurfaceWidth: CGFloat? {
        sourceEditing.documentViewMode == .split ? Metrics.splitPaneMinimumWidth : nil
    }

    private var isUITestModeEnabled: Bool {
        ReaderUITestLaunchConfiguration.current.isUITestModeEnabled
    }
}

struct DocumentSurfaceHost: View {
    let configuration: DocumentSurfaceConfiguration
    let fallbackMarkdown: String

    var body: some View {
        Group {
            if configuration.usesWebSurface {
                MarkdownWebView(
                    htmlDocument: configuration.htmlDocument,
                    documentIdentity: configuration.documentIdentity,
                    accessibilityIdentifier: configuration.accessibilityIdentifier,
                    accessibilityValue: configuration.accessibilityValue,
                    reloadToken: configuration.reloadToken,
                    diagnosticName: configuration.diagnosticName,
                    postLoadStatusScript: configuration.postLoadStatusScript,
                    changedRegionNavigationRequest: configuration.changedRegionNavigationRequest,
                    scrollSyncRequest: configuration.scrollSyncRequest,
                    tocScrollRequest: configuration.tocScrollRequest,
                    supportsInPlaceContentUpdates: configuration.supportsInPlaceContentUpdates,
                    overlayTopInset: configuration.overlayTopInset,
                    reloadAnchorProgress: configuration.reloadAnchorProgress,
                    canAcceptDroppedFileURLs: configuration.canAcceptDroppedFileURLs,
                    onAction: configuration.onAction
                )
            } else {
                fallbackSurface
            }
        }
        .frame(minWidth: configuration.minimumWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fallbackSurface: some View {
        switch configuration.role {
        case .preview:
            NativeMarkdownFallbackView(
                markdown: fallbackMarkdown,
                onRetryPreview: { configuration.onAction(.retryFallback) }
            )
        case .source:
            MarkdownSourceFallbackView(
                markdown: fallbackMarkdown,
                onRetryHighlighting: { configuration.onAction(.retryFallback) }
            )
        }
    }
}

private struct FolderDropBlockedOverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))

            VStack(spacing: 6) {
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 22, weight: .semibold))

                Text("Already Watching a Folder")
                    .font(.headline)

                Text("Stop the current folder watch before dropping another folder.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .foregroundStyle(Color.black)
            .padding(20)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .systemYellow))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange, lineWidth: 2)
            )
        }
    }
}

private struct DocumentSurfaceLayoutView<PreviewSurface: View, SourceSurface: View>: View {
    let documentViewMode: ReaderDocumentViewMode
    let hasOpenDocument: Bool
    let showsLoadingOverlay: Bool
    let loadingOverlayHeadline: String
    let loadingOverlaySubtitle: String?
    let emptyStateVariant: ContentEmptyStateView.Variant
    let currentReaderTheme: ReaderTheme
    let onDroppedFileURLs: ([URL]) -> Void
    let previewSurface: PreviewSurface
    let sourceSurface: SourceSurface

    var body: some View {
        if showsLoadingOverlay {
            DocumentLoadingOverlay(
                theme: currentReaderTheme,
                headline: loadingOverlayHeadline,
                subtitle: loadingOverlaySubtitle
            )
        } else if !hasOpenDocument {
            ContentEmptyStateView(
                variant: emptyStateVariant,
                theme: currentReaderTheme
            )
            .dropDestination(for: URL.self) { urls, _ in
                let fileURLs = urls.filter { $0.isFileURL }
                guard !fileURLs.isEmpty else { return false }
                onDroppedFileURLs(fileURLs)
                return true
            }
        } else {
            switch documentViewMode {
            case .preview:
                previewSurface
            case .split:
                HSplitView {
                    previewSurface
                    sourceSurface
                }
            case .source:
                sourceSurface
            }
        }
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
    return ContentView(
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
        onAction: { _ in },
        isFolderWatchOptionsPresented: .constant(false),
        pendingFolderWatchOpenMode: .constant(.watchChangesOnly),
        pendingFolderWatchScope: .constant(.selectedFolderOnly),
        pendingFolderWatchExcludedSubdirectoryPaths: .constant([])
    )
}
