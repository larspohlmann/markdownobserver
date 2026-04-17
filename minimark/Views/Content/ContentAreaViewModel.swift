import AppKit
import Foundation
import OSLog
import SwiftUI

@MainActor
@Observable
final class ContentAreaViewModel {
    static let splitPaneMinimumWidth: CGFloat = 320

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ContentAreaViewModel"
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

    init(
        document: ReaderDocumentController,
        rendering: ReaderRenderingController,
        sourceEditing: ReaderSourceEditingController,
        externalChange: ReaderExternalChangeController,
        toc: ReaderTOCController,
        settingsStore: ReaderSettingsStore,
        folderWatchState: ContentViewFolderWatchState,
        surfaceViewModel: DocumentSurfaceViewModel,
        onAction: @escaping (ContentViewAction) -> Void
    ) {
        self.document = document
        self.rendering = rendering
        self.sourceEditing = sourceEditing
        self.externalChange = externalChange
        self.toc = toc
        self.settingsStore = settingsStore
        self.folderWatchState = folderWatchState
        self.surfaceViewModel = surfaceViewModel
        self.onAction = onAction
    }

    var statusBarTimestamp: ReaderStatusBarTimestamp? {
        if let date = externalChange.lastExternalChangeAt { return .updated(date) }
        if let date = document.fileLastModifiedAt { return .lastModified(date) }
        if let date = rendering.lastRefreshAt { return .updated(date) }
        return nil
    }

    var currentReaderTheme: ReaderTheme {
        ReaderTheme.theme(for: folderWatchState.effectiveReaderTheme)
    }

    var overlayColorScheme: ColorScheme {
        currentReaderTheme.kind.isDark ? .dark : .light
    }

    var isStatusBannerVisible: Bool {
        document.isCurrentFileMissing || rendering.needsImageDirectoryAccess
    }

    var overlayLayout: OverlayLayoutModel {
        OverlayLayoutModel(
            isSourceEditing: sourceEditing.isSourceEditing,
            isStatusBannerVisible: isStatusBannerVisible
        )
    }

    var emptyStateVariant: ContentEmptyStateView.Variant {
        if let activeWatch = folderWatchState.activeFolderWatch {
            return .folderWatchEmpty(folderName: activeWatch.detailSummaryTitle)
        }
        return .noDocument
    }

    var shouldShowDocumentLoadingOverlay: Bool {
        document.documentLoadState == .loading
            || document.documentLoadState == .settlingAutoOpen
    }

    var loadingOverlayHeadline: String {
        switch document.documentLoadState {
        case .settlingAutoOpen:
            return "Waiting for file contents\u{2026}"
        case .ready, .loading, .deferred:
            return "Loading document\u{2026}"
        }
    }

    var loadingOverlaySubtitle: String? {
        switch document.documentLoadState {
        case .settlingAutoOpen:
            return "The new watched document will appear as soon as writing finishes."
        case .ready, .loading, .deferred:
            return nil
        }
    }

    var minimumSurfaceWidth: CGFloat? {
        sourceEditing.documentViewMode == .split ? Self.splitPaneMinimumWidth : nil
    }

    var canNavigateChangedRegions: Bool {
        surfaceViewModel.canNavigateChangedRegions(
            documentViewMode: sourceEditing.documentViewMode,
            changedRegions: document.changedRegions
        )
    }

    var showSourceEditingControls: Bool {
        document.hasOpenDocument
            && (sourceEditing.documentViewMode != .preview || sourceEditing.isSourceEditing)
    }

    var previewAccessibilitySummary: ReaderPreviewAccessibilitySummary {
        ReaderPreviewAccessibilitySummary(
            fileName: document.fileURL?.lastPathComponent ?? "none",
            regionCount: document.changedRegions.count,
            mode: sourceEditing.documentViewMode
        )
    }

    var previewAccessibilityValue: String {
        previewAccessibilitySummary.description
    }

    var isUITestModeEnabled: Bool {
        ReaderUITestLaunchConfiguration.current.isUITestModeEnabled
    }

    func handleAppear() {
        refreshSourceHTMLFromControllers()
        surfaceViewModel.handleSurfaceAppear(
            renderedHTMLDocument: rendering.renderedHTMLDocument,
            sourceMarkdown: document.sourceMarkdown
        )
    }

    func refreshSourceHTMLFromControllers() {
        surfaceViewModel.refreshSourceHTML(
            markdown: sourceEditing.sourceEditorSeedMarkdown,
            settings: settingsStore.currentSettings,
            isEditable: sourceEditing.isSourceEditing
        )
    }

    func canAcceptDroppedFileURLs(_ fileURLs: [URL]) -> Bool {
        !ReaderFileRouting.containsLikelyDirectoryPath(in: fileURLs)
            || folderWatchState.activeFolderWatch == nil
    }

    func handleDroppedFileURLs(_ fileURLs: [URL]) {
        if let droppedFolderURL = ReaderFileRouting.firstDroppedDirectoryURL(from: fileURLs) {
            guard folderWatchState.activeFolderWatch == nil else { return }
            onAction(.requestFolderWatch(droppedFolderURL))
            return
        }

        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else { return }

        let slotStrategy: FileOpenRequest.SlotStrategy =
            document.fileURL == nil ? .reuseEmptySlotForFirst : .alwaysAppend
        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: markdownURLs,
            origin: .manual,
            slotStrategy: slotStrategy
        )))
    }

    func handlePickedFileURLs(_ fileURLs: [URL]) {
        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else { return }

        let normalizedIncomingURL = ReaderFileRouting.normalizedFileURL(markdownURLs[0])
        let currentURL = document.fileURL.map(ReaderFileRouting.normalizedFileURL)
        if sourceEditing.hasUnsavedDraftChanges, currentURL != normalizedIncomingURL {
            onAction(.presentError(ReaderError.unsavedDraftRequiresResolution))
            return
        }

        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: [markdownURLs[0]],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        )))

        let additionalMarkdownURLs = Array(markdownURLs.dropFirst())
        guard !additionalMarkdownURLs.isEmpty else { return }

        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: additionalMarkdownURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        )))
    }

    func promptForImageDirectoryAccess() {
        guard let directoryURL = document.fileURL?.deletingLastPathComponent() else { return }
        guard let selectedURL = MarkdownOpenPanel.pickFolder(
            directoryURL: directoryURL,
            title: "Grant Image Access",
            message: "Select the folder containing your images to display them in the preview.",
            prompt: "Grant Access"
        ) else { return }
        onAction(.grantImageDirectoryAccess(selectedURL))
    }

    func requestChangeNavigation(_ direction: ReaderChangedRegionNavigationDirection) {
        surfaceViewModel.changeNavigation.requestNavigation(direction)
        surfaceViewModel.splitScrollCoordinator.suppressPreviewBounceBack()
    }

    func dispatchWatchPillAction(_ action: WatchPillAction) {
        switch action {
        case .stop:
            onAction(.stopFolderWatch)
        case .saveFavorite(let name):
            onAction(.saveFolderWatchAsFavorite(name))
        case .removeFavorite:
            onAction(.removeCurrentWatchFromFavorites)
        case .revealInFinder:
            if let url = folderWatchState.activeFolderWatch?.folderURL {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            }
        case .toggleAppearanceLock:
            onAction(.toggleAppearanceLock)
        case .editSubfolders:
            onAction(.editSubfolders)
        }
    }

    func makeSurfaceConfiguration(for surface: DocumentSurfaceRole) -> DocumentSurfaceConfiguration {
        surfaceViewModel.documentSurfaceConfiguration(
            for: surface,
            fileURL: document.fileURL,
            renderedHTMLDocument: rendering.renderedHTMLDocument,
            documentViewMode: sourceEditing.documentViewMode,
            changedRegions: document.changedRegions,
            isSourceEditing: sourceEditing.isSourceEditing,
            overlayTopInset: overlayLayout.insets.scrollTargetTopInset,
            minimumSurfaceWidth: minimumSurfaceWidth,
            tocScrollRequest: toc.scrollRequest,
            canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
            onSharedAction: { action, role in
                self.surfaceViewModel.handleSharedAction(
                    action,
                    for: role,
                    documentViewMode: self.sourceEditing.documentViewMode,
                    onDroppedFileURLs: self.handleDroppedFileURLs,
                    onAction: self.onAction
                )
            },
            onAction: onAction
        )
    }

    func dispatchTopBarAction(_ action: ReaderTopBarAction) {
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
}
