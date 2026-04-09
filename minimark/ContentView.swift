import AppKit
import Foundation
import Combine
import OSLog
import SwiftUI

struct ContentView: View {
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
        let tocScrollRequest: TOCScrollRequest?
        let supportsInPlaceContentUpdates: Bool
        let overlayTopInset: CGFloat
        let reloadAnchorProgress: Double?
        let minimumWidth: CGFloat?
        let onFatalCrash: () -> Void
        let onPostLoadStatus: (String?) -> Void
        let onScrollSyncObservation: (ScrollSyncObservation) -> Void
        let onSourceEdit: (String) -> Void
        let onTOCHeadingsExtracted: ([TOCHeading]) -> Void
        let onDroppedFileURLs: ([URL]) -> Void
        let onDropTargetedChange: (DropTargetingUpdate) -> Void
        let canAcceptDroppedFileURLs: ([URL]) -> Bool
        let onRetryFallback: () -> Void
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "ContentView"
    )

    var readerStore: ReaderStore
    let settingsStore: ReaderSettingsStore
    let folderWatchState: ContentViewFolderWatchState
    let callbacks: ContentViewCallbacks
    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    @StateObject private var splitScrollCoordinator = SplitScrollCoordinator()
    @State private var dragTargetedSurfaces: Set<DocumentSurfaceRole> = []
    @State private var blockedFolderDropTargetedSurfaces: Set<DocumentSurfaceRole> = []
    @State private var previewMode: PreviewMode = .web
    @State private var previewReloadToken = 0
    @State private var sourceMode: SourceMode = .web
    @State private var sourceReloadToken = 0
    @State private var changedRegionNavigationRequestID = 0
    @State private var lastChangedRegionNavigationDirection: ReaderChangedRegionNavigationDirection?
    @State private var currentChangedRegionIndex: Int?
    @State private var cachedSourceHTMLInputs: SourceHTMLInputs?
    @State private var cachedSourceHTMLDocument = ""

    var body: some View {
        interactionAwareView(baseBody)
    }

    private var baseBody: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if readerStore.isCurrentFileMissing {
                    DeletedFileWarningBar(
                        fileName: readerStore.fileDisplayName,
                        message: readerStore.lastError?.message
                    )
                    .padding(.top, ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: overlayTopInset))
                } else if readerStore.needsImageDirectoryAccess {
                    ImageAccessWarningBar {
                        promptForImageDirectoryAccess()
                    }
                    .padding(.top, ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: overlayTopInset))
                }

                documentSurfaceWithOverlays
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
            .onChange(of: readerStore.changedRegions) { _, _ in
                currentChangedRegionIndex = nil
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
            .onChange(of: folderWatchState.activeFolderWatch?.folderURL.standardizedFileURL.path) { _, _ in
                clearDropTargetState()
            }
            .onAppear {
                handleSurfaceAppear()
            }

            ReaderTopBar(
                readerStore: readerStore,
                canStopFolderWatch: folderWatchState.canStopFolderWatch,
                apps: readerStore.openInApplications,
                favoriteWatchedFolders: folderWatchState.favoriteWatchedFolders,
                recentWatchedFolders: folderWatchState.recentWatchedFolders,
                recentManuallyOpenedFiles: folderWatchState.recentManuallyOpenedFiles,
                iconProvider: appIconImage(for:),
                onOpenFiles: { fileURLs in
                    handlePickedFileURLs(fileURLs)
                },
                onOpenApp: { app in
                    readerStore.openCurrentFileInApplication(app)
                },
                onRevealInFinder: {
                    readerStore.revealCurrentFileInFinder()
                },
                onRequestFolderWatch: callbacks.onRequestFolderWatch,
                onStopFolderWatch: callbacks.onStopFolderWatch,
                onStartFavoriteWatch: callbacks.onStartFavoriteWatch,
                onClearFavoriteWatchedFolders: callbacks.onClearFavoriteWatchedFolders,
                onRenameFavoriteWatchedFolder: callbacks.onRenameFavoriteWatchedFolder,
                onRemoveFavoriteWatchedFolder: callbacks.onRemoveFavoriteWatchedFolder,
                onReorderFavoriteWatchedFolders: callbacks.onReorderFavoriteWatchedFolders,
                onStartRecentManuallyOpenedFile: callbacks.onStartRecentManuallyOpenedFile,
                onStartRecentFolderWatch: callbacks.onStartRecentFolderWatch,
                onClearRecentWatchedFolders: callbacks.onClearRecentWatchedFolders,
                onClearRecentManuallyOpenedFiles: callbacks.onClearRecentManuallyOpenedFiles,
                onSaveSourceDraft: {
                    readerStore.saveSourceDraft()
                },
                onDiscardSourceDraft: {
                    readerStore.discardSourceDraft()
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

    private func interactionAwareView<Content: View>(_ view: Content) -> some View {
        view
        .focusedValue(
            \.readerOpenDocumentInCurrentWindow,
            ReaderOpenDocumentInCurrentWindowAction { fileURL in
                let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
                let currentURL = readerStore.fileURL.map(ReaderFileRouting.normalizedFileURL)
                if readerStore.hasUnsavedDraftChanges, currentURL != normalizedURL {
                    readerStore.presentError(ReaderError.unsavedDraftRequiresResolution)
                    return
                }
                callbacks.onRequestFileOpen(FileOpenRequest(
                    fileURLs: [fileURL],
                    origin: .manual,
                    slotStrategy: .replaceSelectedSlot
                ))
            }
        )
        .focusedValue(
            \.readerOpenDocument,
            ReaderOpenDocumentAction { fileURL in
                if readerStore.fileURL == nil {
                    callbacks.onRequestFileOpen(FileOpenRequest(
                        fileURLs: [fileURL],
                        origin: .manual,
                        slotStrategy: .replaceSelectedSlot
                    ))
                } else {
                    callbacks.onRequestFileOpen(FileOpenRequest(
                        fileURLs: [fileURL],
                        origin: .manual,
                        slotStrategy: .alwaysAppend
                    ))
                }
            }
        )
        .focusedValue(
            \.readerOpenAdditionalDocument,
            ReaderOpenAdditionalDocumentAction { fileURL in
                if readerStore.fileURL == nil {
                    callbacks.onRequestFileOpen(FileOpenRequest(
                        fileURLs: [fileURL],
                        origin: .manual,
                        slotStrategy: .replaceSelectedSlot
                    ))
                } else {
                    callbacks.onRequestFileOpen(FileOpenRequest(
                        fileURLs: [fileURL],
                        origin: .manual,
                        slotStrategy: .alwaysAppend
                    ))
                }
            }
        )
        .focusedValue(
            \.readerWatchFolder,
            ReaderWatchFolderAction { folderURL in
                callbacks.onRequestFolderWatch(folderURL)
            }
        )
        .focusedValue(
            \.readerStartRecentFolderWatch,
            ReaderStartRecentFolderWatchAction { entry in
                callbacks.onStartRecentFolderWatch(entry)
            }
        )
        .focusedValue(
            \.readerStopFolderWatch,
            ReaderStopFolderWatchAction {
                guard folderWatchState.canStopFolderWatch else {
                    return
                }
                callbacks.onStopFolderWatch()
            }
        )
        .focusedValue(
            \.readerHasActiveFolderWatch,
            folderWatchState.canStopFolderWatch
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
        .focusedValue(
            \.readerToggleTOC,
            ReaderToggleTOCAction(
                canToggle: !readerStore.tocHeadings.isEmpty,
                toggle: { readerStore.toggleTOC() }
            )
        )
        .onChange(of: isFolderWatchOptionsPresented) { _, isPresented in
            handleFolderWatchOptionsPresentationChange(isPresented)
        }
        .sheet(isPresented: $isFolderWatchOptionsPresented) {
            FolderWatchOptionsSheet(
                folderURL: folderWatchState.pendingFolderWatchURL,
                openMode: $pendingFolderWatchOpenMode,
                scope: $pendingFolderWatchScope,
                excludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths,
                onCancel: callbacks.onCancelFolderWatch,
                onConfirm: callbacks.onConfirmFolderWatch
            )
        }
    }

    private func handleFileIdentityChange() {
        currentChangedRegionIndex = nil
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

        callbacks.onCancelFolderWatch()
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
            guard folderWatchState.activeFolderWatch == nil else {
                return
            }

            callbacks.onRequestFolderWatch(droppedFolderURL)
            return
        }

        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else {
            return
        }

        let slotStrategy: FileOpenRequest.SlotStrategy =
            readerStore.fileURL == nil ? .reuseEmptySlotForFirst : .alwaysAppend
        callbacks.onRequestFileOpen(FileOpenRequest(
            fileURLs: markdownURLs,
            origin: .manual,
            slotStrategy: slotStrategy
        ))
    }

    private func handlePickedFileURLs(_ fileURLs: [URL]) {
        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else {
            return
        }

        let normalizedIncomingURL = ReaderFileRouting.normalizedFileURL(markdownURLs[0])
        let currentURL = readerStore.fileURL.map(ReaderFileRouting.normalizedFileURL)
        if readerStore.hasUnsavedDraftChanges,
           currentURL != normalizedIncomingURL {
            readerStore.presentError(ReaderError.unsavedDraftRequiresResolution)
            return
        }

        callbacks.onRequestFileOpen(FileOpenRequest(
            fileURLs: [markdownURLs[0]],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        let additionalMarkdownURLs = Array(markdownURLs.dropFirst())
        guard !additionalMarkdownURLs.isEmpty else {
            return
        }

        callbacks.onRequestFileOpen(FileOpenRequest(
            fileURLs: additionalMarkdownURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))
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
            hasOpenDocument: readerStore.hasOpenDocument,
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
        if readerStore.isSourceEditing {
            height += ReaderTopBarMetrics.sourceEditingBarHeight
        }
        return height
    }

    private var isStatusBannerVisible: Bool {
        readerStore.isCurrentFileMissing || readerStore.needsImageDirectoryAccess
    }

    private var overlayInsets: ReaderOverlayInsetValues {
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
                if readerStore.isTOCVisible, let anchor {
                    tocOverlay(buttonAnchor: anchor)
                }
            }
            .overlay(alignment: .topLeading) {
                if canNavigateChangedRegions {
                    VStack(alignment: .leading, spacing: 4) {
                        ChangeNavigationPill(
                            currentIndex: currentChangedRegionIndex,
                            totalCount: readerStore.changedRegions.count,
                            onNavigate: requestChangedRegionNavigation
                        )

                        FirstUseHintView(
                            hint: .changeNavigation,
                            message: "Use the arrows to step through changes",
                            settingsStore: settingsStore
                        )
                    }
                    .padding(.top, overlayInsets.leadingOverlayTopPadding)
                    .padding(.leading, 8)
                    .environment(\.colorScheme, overlayColorScheme)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
            .animation(.easeOut(duration: 0.25), value: canNavigateChangedRegions)
            .overlay(alignment: .top) {
                if let activeWatch = folderWatchState.activeFolderWatch {
                    WatchPill(
                        activeFolderWatch: activeWatch,
                        isCurrentWatchAFavorite: folderWatchState.isCurrentWatchAFavorite,
                        canStop: folderWatchState.canStopFolderWatch,
                        onStop: callbacks.onStopFolderWatch,
                        onSaveFavorite: callbacks.onSaveFolderWatchAsFavorite,
                        onRemoveFavorite: callbacks.onRemoveCurrentWatchFromFavorites,
                        onRevealInFinder: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeWatch.folderURL.path)
                        },
                        isAppearanceLocked: folderWatchState.isAppearanceLocked,
                        onToggleAppearanceLock: callbacks.onToggleAppearanceLock,
                        onEditSubfolders: callbacks.onEditSubfolders
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
            .animation(.easeOut(duration: 0.25), value: folderWatchState.activeFolderWatch != nil)
    }

    private var contentUtilityRail: some View {
        ContentUtilityRail(
            hasFile: readerStore.fileURL != nil,
            documentViewMode: readerStore.documentViewMode,
            showEditButton: showSourceEditingControls && !readerStore.isSourceEditing,
            canStartSourceEditing: readerStore.canStartSourceEditing,
            onSetDocumentViewMode: { mode in
                readerStore.setDocumentViewMode(mode)
            },
            onStartSourceEditing: {
                readerStore.startEditingSource()
            },
            hasTOCHeadings: !readerStore.tocHeadings.isEmpty,
            isTOCVisible: Binding(
                get: { readerStore.isTOCVisible },
                set: { readerStore.isTOCVisible = $0 }
            )
        )
    }

    @ViewBuilder
    private func tocOverlay(buttonAnchor: Anchor<CGRect>) -> some View {
        let gap: CGFloat = 8
        let tocColorScheme: ColorScheme = currentReaderTheme.hasLightBackground ? .light : .dark

        GeometryReader { proxy in
            let buttonFrame = proxy[buttonAnchor]
            let panelTrailing = buttonFrame.minX - gap

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { readerStore.isTOCVisible = false }

                TOCPopoverView(
                    headings: readerStore.tocHeadings,
                    onSelect: { heading in
                        handleTOCHeadingSelection(heading)
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

    private func handleTOCHeadingSelection(_ heading: TOCHeading) {
        readerStore.scrollToTOCHeading(heading)
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
        ReaderTheme.theme(for: folderWatchState.effectiveReaderTheme)
    }

    private var emptyStateVariant: ContentEmptyStateView.Variant {
        if let activeWatch = folderWatchState.activeFolderWatch {
            return .folderWatchEmpty(folderName: activeWatch.detailSummaryTitle)
        }
        return .noDocument
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
                tocScrollRequest: readerStore.tocScrollRequest,
                supportsInPlaceContentUpdates: true,
                overlayTopInset: overlayInsets.scrollTargetTopInset,
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
                onTOCHeadingsExtracted: { headings in
                    readerStore.updateTOCHeadings(headings)
                },
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
                tocScrollRequest: readerStore.tocScrollRequest,
                supportsInPlaceContentUpdates: false,
                overlayTopInset: overlayInsets.scrollTargetTopInset,
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
                onTOCHeadingsExtracted: { headings in
                    readerStore.updateTOCHeadings(headings)
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
        if let current = currentChangedRegionIndex {
            if direction == .next, current < count - 1 {
                currentChangedRegionIndex = current + 1
            } else if direction == .previous, current > 0 {
                currentChangedRegionIndex = current - 1
            } else {
                return
            }
        } else {
            currentChangedRegionIndex = direction == .next ? 0 : count - 1
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
        !ReaderFileRouting.containsLikelyDirectoryPath(in: fileURLs) || folderWatchState.activeFolderWatch == nil
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
                    tocScrollRequest: configuration.tocScrollRequest,
                    supportsInPlaceContentUpdates: configuration.supportsInPlaceContentUpdates,
                    overlayTopInset: configuration.overlayTopInset,
                    reloadAnchorProgress: configuration.reloadAnchorProgress,
                    onFatalCrash: configuration.onFatalCrash,
                    onPostLoadStatus: configuration.onPostLoadStatus,
                    onScrollSyncObservation: configuration.onScrollSyncObservation,
                    onSourceEdit: configuration.onSourceEdit,
                    onTOCHeadingsExtracted: configuration.onTOCHeadingsExtracted,
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
    let settingsStore = ReaderSettingsStore()
    let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
    let store = ReaderStore(
        renderer: MarkdownRenderingService(),
        differ: ChangedRegionDiffer(),
        fileWatcher: FileChangeWatcher(),
        folderWatcher: FolderChangeWatcher(),
        settingsStore: settingsStore,
        securityScope: SecurityScopedResourceAccess(),
        fileActions: ReaderFileActionService(),
        systemNotifier: ReaderSystemNotifier.shared,
        folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
            minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
        ),
        settler: settler,
        requestWatchedFolderReauthorization: { _ in nil }
    )
    return ContentView(
        readerStore: store,
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
        callbacks: ContentViewCallbacks(
            onRequestFileOpen: { _ in },
            onRequestFolderWatch: { _ in },
            onConfirmFolderWatch: { _ in },
            onCancelFolderWatch: {},
            onStopFolderWatch: {},
            onSaveFolderWatchAsFavorite: { _ in },
            onRemoveCurrentWatchFromFavorites: {},
            onToggleAppearanceLock: {},
            onStartFavoriteWatch: { _ in },
            onClearFavoriteWatchedFolders: {},
            onRenameFavoriteWatchedFolder: { _, _ in },
            onRemoveFavoriteWatchedFolder: { _ in },
            onReorderFavoriteWatchedFolders: { _ in },
            onStartRecentManuallyOpenedFile: { _ in },
            onStartRecentFolderWatch: { _ in },
            onClearRecentWatchedFolders: {},
            onClearRecentManuallyOpenedFiles: {},
            onEditSubfolders: {}
        ),
        isFolderWatchOptionsPresented: .constant(false),
        pendingFolderWatchOpenMode: .constant(.watchChangesOnly),
        pendingFolderWatchScope: .constant(.selectedFolderOnly),
        pendingFolderWatchExcludedSubdirectoryPaths: .constant([])
    )
}
