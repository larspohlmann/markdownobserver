import AppKit
import Foundation
import Combine
import OSLog
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Metrics {
        static let splitPaneMinimumWidth: CGFloat = 320
    }

    private enum PreviewMode {
        case web
        case nativeFallback
    }

    private enum SourceMode {
        case web
        case plainTextFallback
    }

    fileprivate enum DocumentSurfaceRole: Hashable {
        case preview
        case source

        var counterpart: DocumentSurfaceRole {
            switch self {
            case .preview:
                return .source
            case .source:
                return .preview
            }
        }
    }

    private struct SourceHTMLInputs: Equatable {
        let markdown: String
        let settings: ReaderSettings
        let isEditable: Bool
    }

    fileprivate struct DocumentSurfaceConfiguration {
        let role: DocumentSurfaceRole
        let usesWebSurface: Bool
        let htmlDocument: String
        let documentIdentity: String?
        let accessibilityIdentifier: String
        let accessibilityValue: String
        let reloadToken: Int
        let diagnosticName: String
        let postLoadStatusScript: String?
        let changedRegionNavigationRequest: ChangedRegionNavigationRequest?
        let scrollSyncRequest: ScrollSyncRequest?
        let supportsInPlaceContentUpdates: Bool
        let reloadAnchorProgress: Double?
        let minimumWidth: CGFloat?
        let onFatalCrash: () -> Void
        let onPostLoadStatus: (String?) -> Void
        let onScrollSyncObservation: (ScrollSyncObservation) -> Void
        let onSourceEdit: (String) -> Void
        let onDroppedFileURLs: ([URL]) -> Void
        let onDropTargetedChange: (DropTargetingUpdate) -> Void
        let canAcceptDroppedFileURLs: ([URL]) -> Bool
        let onRetryFallback: () -> Void
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ContentView"
    )

    @ObservedObject var readerStore: ReaderStore
    let openAdditionalDocument: (URL) -> Void
    let openAdditionalDocumentsInCurrentWindow: ([URL]) -> Void
    let openDocumentInCurrentWindow: (URL) -> Void
    let activeFolderWatch: ReaderFolderWatchSession?
    let isFolderWatchInitialScanInProgress: Bool
    let isFolderWatchInitialScanFailed: Bool
    let canStopFolderWatch: Bool
    @Binding var isFolderWatchOptionsPresented: Bool
    let pendingFolderWatchURL: URL?
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]
    let isCurrentWatchAFavorite: Bool
    let favoriteWatchedFolders: [ReaderFavoriteWatchedFolder]
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let onRequestFolderWatch: (URL) -> Void
    let onConfirmFolderWatch: (ReaderFolderWatchOptions) -> Void
    let onCancelFolderWatch: () -> Void
    let onStopFolderWatch: () -> Void
    let onSaveFolderWatchAsFavorite: (String) -> Void
    let onRemoveCurrentWatchFromFavorites: () -> Void
    let onStartFavoriteWatch: (ReaderFavoriteWatchedFolder) -> Void
    let onClearFavoriteWatchedFolders: () -> Void
    let onRenameFavoriteWatchedFolder: (UUID, String) -> Void
    let onRemoveFavoriteWatchedFolder: (UUID) -> Void
    let onReorderFavoriteWatchedFolders: ([UUID]) -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void

    @StateObject private var splitScrollCoordinator = SplitScrollCoordinator()
    @State private var dragTargetedSurfaces: Set<DocumentSurfaceRole> = []
    @State private var blockedFolderDropTargetedSurfaces: Set<DocumentSurfaceRole> = []
    @State private var previewMode: PreviewMode = .web
    @State private var previewReloadToken = 0
    @State private var sourceMode: SourceMode = .web
    @State private var sourceReloadToken = 0
    @State private var changedRegionNavigationRequestID = 0
    @State private var lastChangedRegionNavigationDirection: ReaderChangedRegionNavigationDirection?
    @State private var currentChangedRegionIndex: Int = 0
    @State private var cachedSourceHTMLInputs: SourceHTMLInputs?
    @State private var cachedSourceHTMLDocument = ""

    var body: some View {
        interactionAwareView(baseBody)
    }

    private var baseBody: some View {
        VStack(spacing: 0) {
            ReaderTopBar(
                readerStore: readerStore,
                activeFolderWatch: activeFolderWatch,
                isFolderWatchInitialScanInProgress: isFolderWatchInitialScanInProgress,
                didFolderWatchInitialScanFail: isFolderWatchInitialScanFailed,
                favoriteWatchedFolders: favoriteWatchedFolders,
                recentWatchedFolders: recentWatchedFolders,
                onRequestFolderWatch: onRequestFolderWatch,
                onStartFavoriteWatch: onStartFavoriteWatch,
                onRenameFavoriteWatchedFolder: onRenameFavoriteWatchedFolder,
                onRemoveFavoriteWatchedFolder: onRemoveFavoriteWatchedFolder,
                onReorderFavoriteWatchedFolders: onReorderFavoriteWatchedFolders,
                onStartRecentFolderWatch: onStartRecentFolderWatch,
                onClearRecentWatchedFolders: onClearRecentWatchedFolders,
                onSaveSourceDraft: {
                    readerStore.saveSourceDraft()
                },
                onDiscardSourceDraft: {
                    readerStore.discardSourceDraft()
                }
            )

            VStack(spacing: 0) {
                if readerStore.isCurrentFileMissing {
                    DeletedFileWarningBar(
                        fileName: readerStore.fileDisplayName,
                        message: readerStore.lastError
                    )
                } else if readerStore.needsImageDirectoryAccess {
                    ImageAccessWarningBar {
                        promptForImageDirectoryAccess()
                    }
                }

                documentSurfaceLayout
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if activeFolderWatch != nil {
                            Color.clear.frame(height: 22)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        contentUtilityRail
                    }
                    .overlay(alignment: .topLeading) {
                        if canNavigateChangedRegions {
                            ChangeNavigationPill(
                                currentIndex: currentChangedRegionIndex,
                                totalCount: readerStore.changedRegions.count,
                                onNavigate: requestChangedRegionNavigation
                            )
                        }
                    }
                    .overlay(alignment: .top) {
                        if let activeWatch = activeFolderWatch {
                            WatchPill(
                                activeFolderWatch: activeWatch,
                                isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                                canStop: canStopFolderWatch,
                                onStop: onStopFolderWatch,
                                onSaveFavorite: onSaveFolderWatchAsFavorite,
                                onRemoveFavorite: onRemoveCurrentWatchFromFavorites,
                                onRevealInFinder: {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeWatch.folderURL.path)
                                }
                            )
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isBlockedFolderDropTargeted {
                    FolderDropBlockedOverlayView()
                        .padding(10)
                        .allowsHitTesting(false)
                } else if isDragTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: readerStore.fileURL?.standardizedFileURL.path) { _, _ in
                handleFileIdentityChange()
            }
            .onChange(of: readerStore.changedRegions.count) { _, _ in
                currentChangedRegionIndex = 0
            }
            .onChange(of: previewMode) { _, newValue in
                handlePreviewModeChange(newValue)
            }
            .onChange(of: sourceMode) { _, newValue in
                handleSourceModeChange(newValue)
            }
            .onChange(of: readerStore.documentViewMode) { _, newValue in
                handleDocumentViewModeChange(newValue)
            }
            .onChange(of: sourceHTMLInputs) { _, _ in
                handleSourceHTMLInputsChange()
            }
            .onChange(of: activeFolderWatch?.folderURL.standardizedFileURL.path) { _, _ in
                clearDropTargetState()
            }
            .onAppear {
                handleSurfaceAppear()
            }
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

    private func interactionAwareView<Content: View>(_ view: Content) -> some View {
        view
        .focusedValue(
            \.readerOpenDocumentInCurrentWindow,
            ReaderOpenDocumentInCurrentWindowAction { fileURL in
                openDocumentReplacingCurrentWindow(fileURL)
            }
        )
        .focusedValue(
            \.readerOpenDocument,
            ReaderOpenDocumentAction { fileURL in
                if readerStore.fileURL == nil {
                    readerStore.openFile(at: fileURL)
                } else {
                    openAdditionalDocument(fileURL)
                }
            }
        )
        .focusedValue(
            \.readerOpenAdditionalDocument,
            ReaderOpenAdditionalDocumentAction { fileURL in
                openAdditionalDocument(fileURL)
            }
        )
        .focusedValue(
            \.readerWatchFolder,
            ReaderWatchFolderAction { folderURL in
                onRequestFolderWatch(folderURL)
            }
        )
        .focusedValue(
            \.readerStartRecentFolderWatch,
            ReaderStartRecentFolderWatchAction { entry in
                onStartRecentFolderWatch(entry)
            }
        )
        .focusedValue(
            \.readerStopFolderWatch,
            ReaderStopFolderWatchAction {
                guard canStopFolderWatch else {
                    return
                }
                onStopFolderWatch()
            }
        )
        .focusedValue(
            \.readerHasActiveFolderWatch,
            canStopFolderWatch
        )
        .focusedValue(
            \.readerDocumentViewModeContext,
            ReaderDocumentViewModeContext(
                currentMode: readerStore.documentViewMode,
                canSetMode: readerStore.hasOpenDocument,
                setMode: { mode in
                    readerStore.setDocumentViewMode(mode)
                },
                toggleMode: {
                    readerStore.toggleDocumentViewMode()
                }
            )
        )
        .focusedValue(
            \.readerSourceEditingContext,
            ReaderSourceEditingContext(
                canStartEditing: readerStore.canStartSourceEditing,
                canSave: readerStore.canSaveSourceDraft,
                canDiscard: readerStore.canDiscardSourceDraft,
                startEditing: {
                    readerStore.startEditingSource()
                },
                save: {
                    readerStore.saveSourceDraft()
                },
                discard: {
                    readerStore.discardSourceDraft()
                }
            )
        )
        .focusedValue(
            \.readerChangedRegionNavigation,
            ReaderChangedRegionNavigationAction(
                canNavigate: canNavigateChangedRegions,
                navigate: requestChangedRegionNavigation
            )
        )
        .onChange(of: isFolderWatchOptionsPresented) { _, isPresented in
            handleFolderWatchOptionsPresentationChange(isPresented)
        }
        .sheet(isPresented: $isFolderWatchOptionsPresented) {
            FolderWatchOptionsSheet(
                folderURL: pendingFolderWatchURL,
                openMode: $pendingFolderWatchOpenMode,
                scope: $pendingFolderWatchScope,
                excludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths,
                onCancel: onCancelFolderWatch,
                onConfirm: onConfirmFolderWatch
            )
        }
    }

    private func handleFileIdentityChange() {
        if previewMode == .nativeFallback {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback {
            sourceReloadToken += 1
            sourceMode = .web
        }
        clearDropTargetState()
        splitScrollCoordinator.reset()
    }

    private func handlePreviewModeChange(_ mode: PreviewMode) {
        guard mode == .nativeFallback else {
            return
        }

        clearDropTargetState(for: .preview)
        splitScrollCoordinator.reset()
    }

    private func handleSourceModeChange(_ mode: SourceMode) {
        guard mode == .plainTextFallback else {
            return
        }

        clearDropTargetState(for: .source)
        splitScrollCoordinator.reset()
    }

    private func handleDocumentViewModeChange(_ mode: ReaderDocumentViewMode) {
        guard mode != .split else {
            return
        }

        splitScrollCoordinator.reset()
    }

    private func handleSourceHTMLInputsChange() {
        refreshSourceHTMLDocumentIfNeeded()
    }

    private func handleSurfaceAppear() {
        refreshSourceHTMLDocumentIfNeeded()

        if previewMode == .nativeFallback, !readerStore.renderedHTMLDocument.isEmpty {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback,
           !readerStore.sourceMarkdown.isEmpty {
            sourceReloadToken += 1
            sourceMode = .web
        }
    }

    private func handleFolderWatchOptionsPresentationChange(_ isPresented: Bool) {
        guard !isPresented else {
            return
        }

        onCancelFolderWatch()
    }

    private func promptForImageDirectoryAccess() {
        guard let directoryURL = readerStore.fileURL?.deletingLastPathComponent() else {
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

        readerStore.grantImageDirectoryAccess(folderURL: selectedURL)
    }

    private func handleDroppedFileURLs(_ fileURLs: [URL]) {
        if let droppedFolderURL = ReaderFileRouting.firstDroppedDirectoryURL(from: fileURLs) {
            guard activeFolderWatch == nil else {
                return
            }

            onRequestFolderWatch(droppedFolderURL)
            return
        }

        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else {
            return
        }

        if readerStore.fileURL == nil {
            openDocumentInCurrentWindow(markdownURLs[0])
            let additionalURLs = Array(markdownURLs.dropFirst())
            if !additionalURLs.isEmpty {
                openAdditionalDocumentsInCurrentWindow(additionalURLs)
            }
            return
        }

        openAdditionalDocumentsInCurrentWindow(markdownURLs)
    }

    private func handlePickedFileURLs(_ fileURLs: [URL]) {
        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard let firstURL = markdownURLs.first else {
            return
        }

        guard openDocumentReplacingCurrentWindow(firstURL) else {
            return
        }

        let additionalURLs = Array(markdownURLs.dropFirst())
        guard !additionalURLs.isEmpty else {
            return
        }

        openAdditionalDocumentsInCurrentWindow(additionalURLs)
    }

    @discardableResult
    private func openDocumentReplacingCurrentWindow(_ fileURL: URL) -> Bool {
        let normalizedIncomingURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let currentURL = readerStore.fileURL.map(ReaderFileRouting.normalizedFileURL)
        if readerStore.hasUnsavedDraftChanges,
           currentURL != normalizedIncomingURL {
            readerStore.presentError(ReaderError.unsavedDraftRequiresResolution)
            return false
        }

        openDocumentInCurrentWindow(fileURL)
        return true
    }

    private var previewAccessibilityValue: String {
        let fileName = readerStore.fileURL?.lastPathComponent ?? "none"
        return "file=\(fileName)|regions=\(readerStore.changedRegions.count)|mode=\(readerStore.documentViewMode.rawValue)|surface=preview"
    }

    private var sourceAccessibilityValue: String {
        let fileName = readerStore.fileURL?.lastPathComponent ?? "none"
        return "file=\(fileName)|mode=\(readerStore.documentViewMode.rawValue)|surface=source"
    }

    private var documentSurfaceLayout: some View {
        DocumentSurfaceLayoutView(
            documentViewMode: readerStore.documentViewMode,
            showsLoadingOverlay: shouldShowDocumentLoadingOverlay,
            loadingOverlayHeadline: loadingOverlayHeadline,
            loadingOverlaySubtitle: loadingOverlaySubtitle,
            currentReaderTheme: currentReaderTheme,
            previewSurface: documentSurfacePane(for: .preview),
            sourceSurface: documentSurfacePane(for: .source)
        )
    }

    private var contentUtilityRail: some View {
        ContentUtilityRail(
            hasFile: readerStore.fileURL != nil,
            documentViewMode: readerStore.documentViewMode,
            showEditButton: showSourceEditingControls && !readerStore.isSourceEditing,
            canStartSourceEditing: readerStore.canStartSourceEditing,
            canStopFolderWatch: canStopFolderWatch,
            apps: readerStore.openInApplications,
            favoriteWatchedFolders: favoriteWatchedFolders,
            recentWatchedFolders: recentWatchedFolders,
            recentManuallyOpenedFiles: recentManuallyOpenedFiles,
            iconProvider: appIconImage(for:),
            onSetDocumentViewMode: { mode in
                readerStore.setDocumentViewMode(mode)
            },
            onOpenFiles: { fileURLs in
                handlePickedFileURLs(fileURLs)
            },
            onOpenApp: { app in
                readerStore.openCurrentFileInApplication(app)
            },
            onRevealInFinder: {
                readerStore.revealCurrentFileInFinder()
            },
            onRequestFolderWatch: onRequestFolderWatch,
            onStopFolderWatch: onStopFolderWatch,
            onStartFavoriteWatch: onStartFavoriteWatch,
            onClearFavoriteWatchedFolders: onClearFavoriteWatchedFolders,
            onRenameFavoriteWatchedFolder: onRenameFavoriteWatchedFolder,
            onRemoveFavoriteWatchedFolder: onRemoveFavoriteWatchedFolder,
            onReorderFavoriteWatchedFolders: onReorderFavoriteWatchedFolders,
            onStartRecentManuallyOpenedFile: onStartRecentManuallyOpenedFile,
            onStartRecentFolderWatch: onStartRecentFolderWatch,
            onClearRecentWatchedFolders: onClearRecentWatchedFolders,
            onClearRecentManuallyOpenedFiles: onClearRecentManuallyOpenedFiles,
            onStartSourceEditing: {
                readerStore.startEditingSource()
            }
        )
    }

    private var canNavigateChangedRegions: Bool {
        readerStore.documentViewMode != .source &&
            previewMode == .web &&
            !readerStore.changedRegions.isEmpty
    }

    private var showSourceEditingControls: Bool {
        readerStore.hasOpenDocument &&
            (readerStore.documentViewMode != .preview || readerStore.isSourceEditing)
    }

    private var canSynchronizeSplitScroll: Bool {
        readerStore.documentViewMode == .split &&
            previewMode == .web &&
            sourceMode == .web
    }

    private var currentReaderTheme: ReaderTheme {
        ReaderTheme.theme(for: readerStore.currentSettings.readerTheme)
    }

    private var shouldShowDocumentLoadingOverlay: Bool {
        readerStore.documentLoadState == .loading || readerStore.documentLoadState == .settlingAutoOpen
    }

    private var loadingOverlayHeadline: String {
        switch readerStore.documentLoadState {
        case .settlingAutoOpen:
            return "Waiting for file contents\u{2026}"
        case .ready, .loading, .deferred:
            return "Loading document\u{2026}"
        }
    }

    private var loadingOverlaySubtitle: String? {
        switch readerStore.documentLoadState {
        case .settlingAutoOpen:
            return "The new watched document will appear as soon as writing finishes."
        case .ready, .loading, .deferred:
            return nil
        }
    }

    private var isDragTargeted: Bool {
        !dragTargetedSurfaces.isEmpty
    }

    private var isBlockedFolderDropTargeted: Bool {
        !blockedFolderDropTargetedSurfaces.isEmpty
    }

    private var minimumSurfaceWidth: CGFloat? {
        readerStore.documentViewMode == .split ? Metrics.splitPaneMinimumWidth : nil
    }

    private var sourceHTMLInputs: SourceHTMLInputs {
        SourceHTMLInputs(
            markdown: readerStore.sourceEditorSeedMarkdown,
            settings: readerStore.currentSettings,
            isEditable: readerStore.isSourceEditing
        )
    }

    private func documentSurfacePane(for surface: DocumentSurfaceRole) -> some View {
        DocumentSurfaceHost(
            configuration: documentSurfaceConfiguration(for: surface),
            fallbackMarkdown: readerStore.sourceMarkdown
        )
    }

    private func documentSurfaceConfiguration(for surface: DocumentSurfaceRole) -> DocumentSurfaceConfiguration {
        switch surface {
        case .preview:
            return DocumentSurfaceConfiguration(
                role: surface,
                usesWebSurface: previewMode == .web,
                htmlDocument: readerStore.renderedHTMLDocument,
                documentIdentity: readerStore.fileURL?.standardizedFileURL.path,
                accessibilityIdentifier: "reader-preview",
                accessibilityValue: previewAccessibilityValue,
                reloadToken: previewReloadToken,
                diagnosticName: "reader-preview",
                postLoadStatusScript: nil,
                changedRegionNavigationRequest: previewChangedRegionNavigationRequest,
                scrollSyncRequest: splitScrollRequest(for: surface),
                supportsInPlaceContentUpdates: true,
                reloadAnchorProgress: previewReloadAnchorProgress,
                minimumWidth: minimumSurfaceWidth,
                onFatalCrash: {
                    handleFatalCrash(for: surface)
                },
                onPostLoadStatus: { status in
                    handlePostLoadStatus(status, for: surface)
                },
                onScrollSyncObservation: { observation in
                    handleScrollSyncObservation(observation, from: surface)
                },
                onSourceEdit: { _ in },
                onDroppedFileURLs: handleDroppedFileURLs,
                onDropTargetedChange: { update in
                    updateDropTargetState(for: surface, update: update)
                },
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onRetryFallback: {
                    previewReloadToken += 1
                    previewMode = .web
                }
            )
        case .source:
            return DocumentSurfaceConfiguration(
                role: surface,
                usesWebSurface: sourceMode == .web,
                htmlDocument: cachedSourceHTMLDocument,
                documentIdentity: sourceDocumentIdentity,
                accessibilityIdentifier: "reader-source",
                accessibilityValue: sourceAccessibilityValue,
                reloadToken: sourceReloadToken,
                diagnosticName: "reader-source",
                postLoadStatusScript: "window.__minimarkSourceBootstrapStatus || null",
                changedRegionNavigationRequest: nil,
                scrollSyncRequest: splitScrollRequest(for: surface),
                supportsInPlaceContentUpdates: false,
                reloadAnchorProgress: nil,
                minimumWidth: minimumSurfaceWidth,
                onFatalCrash: {
                    handleFatalCrash(for: surface)
                },
                onPostLoadStatus: { status in
                    handlePostLoadStatus(status, for: surface)
                },
                onScrollSyncObservation: { observation in
                    handleScrollSyncObservation(observation, from: surface)
                },
                onSourceEdit: { markdown in
                    readerStore.updateSourceDraft(markdown)
                },
                onDroppedFileURLs: handleDroppedFileURLs,
                onDropTargetedChange: { update in
                    updateDropTargetState(for: surface, update: update)
                },
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onRetryFallback: {
                    sourceReloadToken += 1
                    sourceMode = .web
                }
            )
        }
    }

    private var sourceDocumentIdentity: String? {
        guard let path = readerStore.fileURL?.standardizedFileURL.path else {
            return nil
        }

        return "\(path)|source"
    }

    private var previewChangedRegionNavigationRequest: ChangedRegionNavigationRequest? {
        guard canNavigateChangedRegions,
              let lastChangedRegionNavigationDirection else {
            return nil
        }

        return ChangedRegionNavigationRequest(
            id: changedRegionNavigationRequestID,
            direction: lastChangedRegionNavigationDirection
        )
    }

    private func requestChangedRegionNavigation(_ direction: ReaderChangedRegionNavigationDirection) {
        guard canNavigateChangedRegions else {
            return
        }

        let count = readerStore.changedRegions.count
        if direction == .next {
            currentChangedRegionIndex = currentChangedRegionIndex >= count - 1 ? 0 : currentChangedRegionIndex + 1
        } else {
            currentChangedRegionIndex = currentChangedRegionIndex <= 0 ? count - 1 : currentChangedRegionIndex - 1
        }

        lastChangedRegionNavigationDirection = direction
        changedRegionNavigationRequestID += 1
    }

    private func handleFatalCrash(for surface: DocumentSurfaceRole) {
        switch surface {
        case .preview:
            Self.logger.error("preview web surface hit fatal crash and fell back to native text")
            previewMode = .nativeFallback
        case .source:
            Self.logger.error("source web surface hit fatal crash and fell back to plain text")
            sourceMode = .plainTextFallback
        }
    }

    private func handlePostLoadStatus(_ status: String?, for surface: DocumentSurfaceRole) {
        guard surface == .source else {
            return
        }

        guard let status else {
            Self.logger.error("source post-load status probe returned no status")
            sourceMode = .plainTextFallback
            return
        }

        guard status == "ready" else {
            Self.logger.error("source bootstrap status was \(status, privacy: .public); falling back to plain text")
            sourceMode = .plainTextFallback
            return
        }

        Self.logger.debug("source bootstrap completed successfully")
    }

    private func refreshSourceHTMLDocumentIfNeeded() {
        let inputs = sourceHTMLInputs
        guard cachedSourceHTMLInputs != inputs else {
            return
        }

        cachedSourceHTMLInputs = inputs
        cachedSourceHTMLDocument = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: inputs.markdown,
            settings: inputs.settings,
            isEditable: inputs.isEditable
        )
    }

    private func updateDropTargetState(for surface: DocumentSurfaceRole, update: DropTargetingUpdate) {
        if update.isTargeted {
            dragTargetedSurfaces.insert(surface)
        } else {
            dragTargetedSurfaces.remove(surface)
        }

        let isBlockedFolderDrop = update.isTargeted && !update.canDrop && update.containsDirectoryHint
        if isBlockedFolderDrop {
            blockedFolderDropTargetedSurfaces.insert(surface)
        } else {
            blockedFolderDropTargetedSurfaces.remove(surface)
        }
    }

    private func clearDropTargetState(for surface: DocumentSurfaceRole? = nil) {
        guard let surface else {
            dragTargetedSurfaces.removeAll()
            blockedFolderDropTargetedSurfaces.removeAll()
            return
        }

        dragTargetedSurfaces.remove(surface)
        blockedFolderDropTargetedSurfaces.remove(surface)
    }

    private func canAcceptDroppedFileURLs(_ fileURLs: [URL]) -> Bool {
        !ReaderFileRouting.containsLikelyDirectoryPath(in: fileURLs) || activeFolderWatch == nil
    }

    private func splitScrollRequest(for surface: DocumentSurfaceRole) -> ScrollSyncRequest? {
        guard canSynchronizeSplitScroll else {
            return nil
        }

        return splitScrollCoordinator.request(for: surface)
    }

    private var previewReloadAnchorProgress: Double? {
        guard canSynchronizeSplitScroll,
              readerStore.isSourceEditing else {
            return nil
        }

        return splitScrollCoordinator.latestObservedProgress(for: .source)
    }

    private func handleScrollSyncObservation(
        _ observation: ScrollSyncObservation,
        from surface: DocumentSurfaceRole
    ) {
        splitScrollCoordinator.handleObservation(
            observation,
            from: surface,
            shouldSync: canSynchronizeSplitScroll
        )
    }

    private var isUITestModeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-minimark-ui-test")
    }
}

private struct DocumentSurfaceHost: View {
    let configuration: ContentView.DocumentSurfaceConfiguration
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
                    supportsInPlaceContentUpdates: configuration.supportsInPlaceContentUpdates,
                    reloadAnchorProgress: configuration.reloadAnchorProgress,
                    onFatalCrash: configuration.onFatalCrash,
                    onPostLoadStatus: configuration.onPostLoadStatus,
                    onScrollSyncObservation: configuration.onScrollSyncObservation,
                    onSourceEdit: configuration.onSourceEdit,
                    onDroppedFileURLs: configuration.onDroppedFileURLs,
                    onDropTargetedChange: configuration.onDropTargetedChange,
                    canAcceptDroppedFileURLs: configuration.canAcceptDroppedFileURLs
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
                onRetryPreview: configuration.onRetryFallback
            )
        case .source:
            MarkdownSourceFallbackView(
                markdown: fallbackMarkdown,
                onRetryHighlighting: configuration.onRetryFallback
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
    let showsLoadingOverlay: Bool
    let loadingOverlayHeadline: String
    let loadingOverlaySubtitle: String?
    let currentReaderTheme: ReaderTheme
    let previewSurface: PreviewSurface
    let sourceSurface: SourceSurface

    var body: some View {
        if showsLoadingOverlay {
            DocumentLoadingOverlay(
                theme: currentReaderTheme,
                headline: loadingOverlayHeadline,
                subtitle: loadingOverlaySubtitle
            )
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

@MainActor
private final class SplitScrollCoordinator: ObservableObject {
    @Published private var previewRequest: ScrollSyncRequest?
    @Published private var sourceRequest: ScrollSyncRequest?

    private var nextRequestID = 0
    private var lastRequestedProgressByRole: [ContentView.DocumentSurfaceRole: Double] = [:]
    private var lastObservedProgressByRole: [ContentView.DocumentSurfaceRole: Double] = [:]

    func request(for role: ContentView.DocumentSurfaceRole) -> ScrollSyncRequest? {
        switch role {
        case .preview:
            return previewRequest
        case .source:
            return sourceRequest
        }
    }

    func handleObservation(
        _ observation: ScrollSyncObservation,
        from role: ContentView.DocumentSurfaceRole,
        shouldSync: Bool
    ) {
        lastObservedProgressByRole[role] = observation.progress

        guard shouldSync, !observation.isProgrammatic else {
            return
        }

        let targetRole = role.counterpart
        if let lastProgress = lastRequestedProgressByRole[targetRole],
           abs(lastProgress - observation.progress) < 0.003 {
            return
        }

        nextRequestID += 1
        let request = ScrollSyncRequest(id: nextRequestID, progress: observation.progress)
        lastRequestedProgressByRole[targetRole] = observation.progress

        switch targetRole {
        case .preview:
            previewRequest = request
        case .source:
            sourceRequest = request
        }
    }

    func latestObservedProgress(for role: ContentView.DocumentSurfaceRole) -> Double? {
        lastObservedProgressByRole[role]
    }

    func reset() {
        previewRequest = nil
        sourceRequest = nil
        lastRequestedProgressByRole.removeAll()
        lastObservedProgressByRole.removeAll()
    }
}

#Preview {
    ContentView(
        readerStore: ReaderStore(),
        openAdditionalDocument: { _ in },
        openAdditionalDocumentsInCurrentWindow: { _ in },
        openDocumentInCurrentWindow: { _ in },
        activeFolderWatch: nil,
        isFolderWatchInitialScanInProgress: false,
        isFolderWatchInitialScanFailed: false,
        canStopFolderWatch: false,
        isFolderWatchOptionsPresented: .constant(false),
        pendingFolderWatchURL: nil,
        pendingFolderWatchOpenMode: .constant(.watchChangesOnly),
        pendingFolderWatchScope: .constant(.selectedFolderOnly),
        pendingFolderWatchExcludedSubdirectoryPaths: .constant([]),
        isCurrentWatchAFavorite: false,
        favoriteWatchedFolders: [],
        recentWatchedFolders: [],
        recentManuallyOpenedFiles: [],
        onRequestFolderWatch: { _ in },
        onConfirmFolderWatch: { _ in },
        onCancelFolderWatch: {},
        onStopFolderWatch: {},
        onSaveFolderWatchAsFavorite: { _ in },
        onRemoveCurrentWatchFromFavorites: {},
        onStartFavoriteWatch: { _ in },
        onClearFavoriteWatchedFolders: {},
        onRenameFavoriteWatchedFolder: { _, _ in },
        onRemoveFavoriteWatchedFolder: { _ in },
        onReorderFavoriteWatchedFolders: { _ in },
        onStartRecentManuallyOpenedFile: { _ in },
        onStartRecentFolderWatch: { _ in },
        onClearRecentWatchedFolders: {},
        onClearRecentManuallyOpenedFiles: {}
    )
}
