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
        let onDropTargetedChange: (Bool) -> Void
        let onRetryFallback: () -> Void
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ContentView"
    )

    @ObservedObject var readerStore: ReaderStore
    let openAdditionalDocument: (URL) -> Void
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
    let recentWatchedFolders: [ReaderRecentWatchedFolder]
    let recentManuallyOpenedFiles: [ReaderRecentOpenedFile]
    let onRequestFolderWatch: (URL) -> Void
    let onConfirmFolderWatch: (ReaderFolderWatchOptions) -> Void
    let onCancelFolderWatch: () -> Void
    let onStopFolderWatch: () -> Void
    let onStartRecentManuallyOpenedFile: (ReaderRecentOpenedFile) -> Void
    let onStartRecentFolderWatch: (ReaderRecentWatchedFolder) -> Void
    let onClearRecentWatchedFolders: () -> Void
    let onClearRecentManuallyOpenedFiles: () -> Void

    @StateObject private var splitScrollCoordinator = SplitScrollCoordinator()
    @State private var dragTargetedSurfaces: Set<DocumentSurfaceRole> = []
    @State private var previewMode: PreviewMode = .web
    @State private var previewReloadToken = 0
    @State private var sourceMode: SourceMode = .web
    @State private var sourceReloadToken = 0
    @State private var changedRegionNavigationRequestID = 0
    @State private var lastChangedRegionNavigationDirection: ReaderChangedRegionNavigationDirection?
    @State private var cachedSourceHTMLInputs: SourceHTMLInputs?
    @State private var cachedSourceHTMLDocument = ""

    var body: some View {
        interactionAwareView(baseBody)
    }

    private var baseBody: some View {
        VStack(spacing: 0) {
            ReaderTopBar(
                readerStore: readerStore,
                documentViewMode: readerStore.documentViewMode,
                showSourceEditingControls: showSourceEditingControls,
                activeFolderWatch: activeFolderWatch,
                isFolderWatchInitialScanInProgress: isFolderWatchInitialScanInProgress,
                didFolderWatchInitialScanFail: isFolderWatchInitialScanFailed,
                folderWatchHighlightColor: folderWatchHighlightColor,
                canNavigateChangedRegions: canNavigateChangedRegions,
                canStopFolderWatch: canStopFolderWatch,
                recentWatchedFolders: recentWatchedFolders,
                recentManuallyOpenedFiles: recentManuallyOpenedFiles,
                onNavigateChangedRegion: requestChangedRegionNavigation,
                onSetDocumentViewMode: { mode in
                    readerStore.setDocumentViewMode(mode)
                },
                onOpenFile: { fileURL in
                    openDocumentReplacingCurrentWindow(fileURL)
                },
                onRequestFolderWatch: onRequestFolderWatch,
                onStopFolderWatch: onStopFolderWatch,
                onStartRecentManuallyOpenedFile: onStartRecentManuallyOpenedFile,
                onStartRecentFolderWatch: onStartRecentFolderWatch,
                onClearRecentWatchedFolders: onClearRecentWatchedFolders,
                onClearRecentManuallyOpenedFiles: onClearRecentManuallyOpenedFiles,
                onStartSourceEditing: {
                    readerStore.startEditingSource()
                },
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
                }

                documentSurfaceLayout
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isDragTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: readerStore.fileURL?.standardizedFileURL.path) { _, _ in
                handleFileIdentityChange()
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
            .onAppear {
                handleSurfaceAppear()
            }

            if activeFolderWatch != nil || readerStore.hasOpenDocument {
                ReaderStatusBar(
                    activeFolderWatch: activeFolderWatch,
                    watchIndicatorColor: folderWatchHighlightColor,
                    canStopFolderWatch: canStopFolderWatch,
                    statusTimestamp: readerStore.statusBarTimestamp,
                    onStopFolderWatch: onStopFolderWatch
                )
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
        dragTargetedSurfaces.removeAll()
        splitScrollCoordinator.reset()
    }

    private func handlePreviewModeChange(_ mode: PreviewMode) {
        guard mode == .nativeFallback else {
            return
        }

        dragTargetedSurfaces.remove(.preview)
        splitScrollCoordinator.reset()
    }

    private func handleSourceModeChange(_ mode: SourceMode) {
        guard mode == .plainTextFallback else {
            return
        }

        dragTargetedSurfaces.remove(.source)
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

    private func handleDroppedFileURLs(_ fileURLs: [URL]) {
        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else {
            return
        }

        if readerStore.fileURL == nil {
            openDocumentInCurrentWindow(markdownURLs[0])
            for fileURL in markdownURLs.dropFirst() {
                openAdditionalDocument(fileURL)
            }
            return
        }

        for fileURL in markdownURLs {
            openAdditionalDocument(fileURL)
        }
    }

    private func openDocumentReplacingCurrentWindow(_ fileURL: URL) {
        let normalizedIncomingURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let currentURL = readerStore.fileURL.map(ReaderFileRouting.normalizedFileURL)
        if readerStore.hasUnsavedDraftChanges,
           currentURL != normalizedIncomingURL {
            readerStore.presentError(ReaderError.unsavedDraftRequiresResolution)
            return
        }

        openDocumentInCurrentWindow(fileURL)
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
            currentReaderTheme: currentReaderTheme,
            previewSurface: documentSurfacePane(for: .preview),
            sourceSurface: documentSurfacePane(for: .source)
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

    private var folderWatchHighlightColor: Color {
        Color.folderWatchHighlight(for: readerStore.currentSettings, colorScheme: colorScheme)
    }

    private var shouldShowDocumentLoadingOverlay: Bool {
        readerStore.documentLoadState == .settlingAutoOpen
    }

    private var isDragTargeted: Bool {
        !dragTargetedSurfaces.isEmpty
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
                onDropTargetedChange: { isTargeted in
                    updateDropTargetState(for: surface, isTargeted: isTargeted)
                },
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
                onDropTargetedChange: { isTargeted in
                    updateDropTargetState(for: surface, isTargeted: isTargeted)
                },
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

    private func updateDropTargetState(for surface: DocumentSurfaceRole, isTargeted: Bool) {
        if isTargeted {
            dragTargetedSurfaces.insert(surface)
        } else {
            dragTargetedSurfaces.remove(surface)
        }
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
                    onDropTargetedChange: configuration.onDropTargetedChange
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

private struct DocumentSurfaceLayoutView<PreviewSurface: View, SourceSurface: View>: View {
    let documentViewMode: ReaderDocumentViewMode
    let showsLoadingOverlay: Bool
    let currentReaderTheme: ReaderTheme
    let previewSurface: PreviewSurface
    let sourceSurface: SourceSurface

    var body: some View {
        if showsLoadingOverlay {
            DocumentLoadingOverlay(theme: currentReaderTheme)
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
        recentWatchedFolders: [],
        recentManuallyOpenedFiles: [],
        onRequestFolderWatch: { _ in },
        onConfirmFolderWatch: { _ in },
        onCancelFolderWatch: {},
        onStopFolderWatch: {},
        onStartRecentManuallyOpenedFile: { _ in },
        onStartRecentFolderWatch: { _ in },
        onClearRecentWatchedFolders: {},
        onClearRecentManuallyOpenedFiles: {}
    )
}
