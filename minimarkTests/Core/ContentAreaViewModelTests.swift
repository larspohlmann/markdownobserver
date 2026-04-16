import AppKit
import Foundation
import Testing
@testable import minimark

@MainActor
private func makeTestViewModel(
    folderWatchState: ContentViewFolderWatchState = .testEmpty
) -> (ContentAreaViewModel, ReaderDocumentController, ReaderRenderingController, ReaderSourceEditingController) {
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
