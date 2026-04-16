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

    // MARK: - Derivations

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

    var previewAccessibilityValue: String {
        let fileName = document.fileURL?.lastPathComponent ?? "none"
        return "file=\(fileName)|regions=\(document.changedRegions.count)|mode=\(sourceEditing.documentViewMode.rawValue)|surface=preview"
    }

    var isUITestModeEnabled: Bool {
        ReaderUITestLaunchConfiguration.current.isUITestModeEnabled
    }

    // Actions will be added in Task 3.
}
