import Foundation
import Testing
@testable import minimark

@MainActor
private func makeTestViewModel(
    folderWatchState: ContentViewFolderWatchState = .testEmpty
) -> (ContentAreaViewModel, DocumentController, RenderingController, SourceEditingController) {
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
    return (viewModel, document, rendering, sourceEditing)
}

extension ContentViewFolderWatchState {
    static let testEmpty = ContentViewFolderWatchState(
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
}

@Suite
struct ContentAreaViewModelTests {

    @Test @MainActor func emptyStateVariantWithoutActiveWatchIsNoDocument() {
        let (viewModel, _, _, _) = makeTestViewModel()
        #expect(viewModel.emptyStateVariant == .noDocument)
    }

    @Test @MainActor func isStatusBannerVisibleIsFalseByDefault() {
        let (viewModel, _, _, _) = makeTestViewModel()
        #expect(viewModel.isStatusBannerVisible == false)
    }

    @Test @MainActor func minimumSurfaceWidthIsNilOutsideSplit() {
        let (viewModel, _, _, sourceEditing) = makeTestViewModel()
        sourceEditing.setViewMode(.preview, hasOpenDocument: false)
        #expect(viewModel.minimumSurfaceWidth == nil)
    }

    @Test @MainActor func minimumSurfaceWidthIsSetInSplitMode() {
        let (viewModel, _, _, sourceEditing) = makeTestViewModel()
        sourceEditing.setViewMode(.split, hasOpenDocument: true)
        #expect(viewModel.minimumSurfaceWidth == 320)
    }

    @Test @MainActor func canNavigateChangedRegionsIsFalseWhenEmpty() {
        let (viewModel, _, _, _) = makeTestViewModel()
        #expect(viewModel.canNavigateChangedRegions == false)
    }

    @Test @MainActor func overlayLayoutReflectsSourceEditingFlag() {
        let (viewModel, _, _, sourceEditing) = makeTestViewModel()
        sourceEditing.setViewMode(.source, hasOpenDocument: true)
        sourceEditing.isSourceEditing = true
        #expect(viewModel.overlayLayout.isSourceEditing == true)
    }
}

@MainActor
private func settle(iterations: Int = 30) async {
    for _ in 0..<iterations {
        await Task.yield()
    }
}

/// Awaits the first MainActor tick after VM construction so that the observation
/// coordinator's per-property Tasks have registered their `withObservationTracking`
/// interest — only then will subsequent mutations fire the reactions under test.
@MainActor
private func waitForObservationSetup() async {
    await settle()
}

@Suite(.serialized)
struct ContentAreaViewModelObservationTests {

    @Test @MainActor
    func changingChangedRegionsResetsNavigationIndex() async {
        let (viewModel, document, _, _) = makeTestViewModel()
        await waitForObservationSetup()
        viewModel.surfaceViewModel.changeNavigation.handleNavigationResult(index: 2)
        #expect(viewModel.surfaceViewModel.changeNavigation.currentIndex == 2)

        document.changedRegions = [
            ChangedRegion(blockIndex: 0, lineRange: 0...0, kind: .added)
        ]
        await settle()

        #expect(viewModel.surfaceViewModel.changeNavigation.currentIndex == nil)
    }

    @Test @MainActor
    func changingFileURLResetsNavigationAndClearsDrop() async {
        let (viewModel, document, _, _) = makeTestViewModel()
        await waitForObservationSetup()
        viewModel.surfaceViewModel.changeNavigation.requestNavigation(.next)
        viewModel.surfaceViewModel.changeNavigation.handleNavigationResult(index: 5)
        viewModel.surfaceViewModel.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(
                isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true
            )
        )
        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == true)

        document.fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("a.md")
        await settle()

        #expect(viewModel.surfaceViewModel.changeNavigation.currentIndex == nil)
        #expect(viewModel.surfaceViewModel.changeNavigation.currentRequest == nil)
        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == false)
    }

    @Test @MainActor
    func flippingIsSourceEditingRefreshesSourceHTMLCache() async {
        let (viewModel, _, _, sourceEditing) = makeTestViewModel()
        await waitForObservationSetup()
        #expect(viewModel.surfaceViewModel.sourceHTMLCache.document.isEmpty)

        sourceEditing.isSourceEditing = true
        await settle()

        #expect(!viewModel.surfaceViewModel.sourceHTMLCache.document.isEmpty)
    }

    @Test @MainActor
    func previewFallbackClearsPreviewDropTargeting() async {
        let (viewModel, _, _, _) = makeTestViewModel()
        await waitForObservationSetup()
        viewModel.surfaceViewModel.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(
                isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true
            )
        )
        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == true)

        viewModel.surfaceViewModel.previewMode = .nativeFallback
        await settle()

        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == false)
    }

    @Test @MainActor
    func applyingNewFolderWatchStateClearsDropTargeting() async {
        let (viewModel, _, _, _) = makeTestViewModel()
        await waitForObservationSetup()
        viewModel.surfaceViewModel.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(
                isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true
            )
        )
        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == true)

        let folderURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("watched")
        let nextState = ContentViewFolderWatchState(
            activeFolderWatch: FolderWatchSession(
                folderURL: folderURL,
                options: .default,
                startedAt: Date()
            ),
            isFolderWatchInitialScanInProgress: false,
            isFolderWatchInitialScanFailed: false,
            canStopFolderWatch: true,
            pendingFolderWatchURL: nil,
            isCurrentWatchAFavorite: false,
            favoriteWatchedFolders: [],
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: [],
            isAppearanceLocked: false,
            effectiveReaderTheme: .blackOnWhite
        )
        viewModel.applyHostInputs(folderWatchState: nextState, onAction: { _ in })
        await settle()

        #expect(viewModel.surfaceViewModel.dropTargeting.isDragTargeted == false)
    }
}

@Suite
struct ContentAreaViewModelDropRoutingTests {

    @Test @MainActor func canAcceptDropsWhenNoFolderIsWatched() {
        let (viewModel, _, _, _) = makeTestViewModel()
        let urls = [URL(fileURLWithPath: "/tmp/example.md")]
        #expect(viewModel.canAcceptDroppedFileURLs(urls) == true)
    }

    @Test @MainActor func handleDroppedMarkdownFiresRequestFileOpen() {
        var captured: [ContentViewAction] = []
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
        let viewModel = ContentAreaViewModel(
            document: DocumentController(
                fileDependencies: fileDeps,
                settingsStore: settingsStore,
                settler: settler
            ),
            rendering: RenderingController(
                renderingDependencies: renderingDeps,
                settingsStore: settingsStore,
                securityScopeResolver: securityScopeResolver
            ),
            sourceEditing: SourceEditingController(),
            externalChange: ExternalChangeController(),
            toc: TOCController(),
            settingsStore: settingsStore,
            folderWatchState: .testEmpty,
            surfaceViewModel: DocumentSurfaceViewModel(),
            onAction: { captured.append($0) }
        )
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sample.md")
        viewModel.handleDroppedFileURLs([url])
        #expect(captured.contains(where: {
            if case .requestFileOpen = $0 { return true } else { return false }
        }))
    }
}
