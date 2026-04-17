import SwiftUI

struct ContentViewFocusedValues: ViewModifier {
    let document: ReaderDocumentController
    let sourceEditing: ReaderSourceEditingController
    let toc: ReaderTOCController
    let folderWatchState: ContentViewFolderWatchState
    let onAction: (ContentViewAction) -> Void
    let canNavigateChangedRegions: Bool
    let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void
    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: FolderWatchOpenMode
    @Binding var pendingFolderWatchScope: FolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    private func openOrAppendDocument(_ fileURL: URL) {
        let strategy: FileOpenRequest.SlotStrategy =
            document.fileURL == nil ? .replaceSelectedSlot : .alwaysAppend
        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: [fileURL],
            origin: .manual,
            slotStrategy: strategy
        )))
    }

    func body(content: Content) -> some View {
        content
            .focusedValue(
                \.readerOpenDocumentInCurrentWindow,
                ReaderOpenDocumentInCurrentWindowAction { fileURL in
                    let normalizedURL = ReaderFileRouting.normalizedFileURL(fileURL)
                    let currentURL = document.fileURL.map(ReaderFileRouting.normalizedFileURL)
                    if sourceEditing.hasUnsavedDraftChanges, currentURL != normalizedURL {
                        onAction(.presentError(ReaderError.unsavedDraftRequiresResolution))
                        return
                    }
                    onAction(.requestFileOpen(FileOpenRequest(
                        fileURLs: [fileURL],
                        origin: .manual,
                        slotStrategy: .replaceSelectedSlot
                    )))
                }
            )
            .focusedValue(
                \.readerOpenDocument,
                ReaderOpenDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedValue(
                \.readerOpenAdditionalDocument,
                ReaderOpenAdditionalDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedValue(
                \.readerWatchFolder,
                ReaderWatchFolderAction { folderURL in
                    onAction(.requestFolderWatch(folderURL))
                }
            )
            .focusedValue(
                \.readerStartRecentFolderWatch,
                ReaderStartRecentFolderWatchAction { entry in
                    onAction(.startRecentFolderWatch(entry))
                }
            )
            .focusedValue(
                \.readerStopFolderWatch,
                ReaderStopFolderWatchAction {
                    guard folderWatchState.canStopFolderWatch else {
                        return
                    }
                    onAction(.stopFolderWatch)
                }
            )
            .focusedValue(
                \.readerHasActiveFolderWatch,
                folderWatchState.canStopFolderWatch
            )
            .focusedValue(
                \.readerDocumentViewModeContext,
                ReaderDocumentViewModeContext(
                    currentMode: sourceEditing.documentViewMode,
                    canSetMode: document.hasOpenDocument,
                    setMode: { mode in
                        sourceEditing.setViewMode(mode, hasOpenDocument: document.hasOpenDocument)
                    },
                    toggleMode: {
                        sourceEditing.toggleViewMode()
                    }
                )
            )
            .focusedValue(
                \.readerSourceEditingContext,
                ReaderSourceEditingContext(
                    canStartEditing: (document.hasOpenDocument && !document.isCurrentFileMissing && !sourceEditing.isSourceEditing),
                    canSave: sourceEditing.canSaveSourceDraft,
                    canDiscard: sourceEditing.canDiscardSourceDraft,
                    startEditing: {
                        onAction(.startSourceEditing)
                    },
                    save: {
                        onAction(.saveSourceDraft)
                    },
                    discard: {
                        onAction(.discardSourceDraft)
                    }
                )
            )
            .focusedValue(
                \.readerChangedRegionNavigation,
                ReaderChangedRegionNavigationAction(
                    canNavigate: canNavigateChangedRegions,
                    navigate: onNavigateChangedRegion
                )
            )
            .focusedValue(
                \.readerToggleTOC,
                ReaderToggleTOCAction(
                    canToggle: !toc.headings.isEmpty,
                    toggle: { toc.toggle() }
                )
            )
            .onChange(of: isFolderWatchOptionsPresented) { _, isPresented in
                guard !isPresented else { return }
                onAction(.cancelFolderWatch)
            }
            .sheet(isPresented: $isFolderWatchOptionsPresented) {
                FolderWatchOptionsSheet(
                    folderURL: folderWatchState.pendingFolderWatchURL,
                    openMode: $pendingFolderWatchOpenMode,
                    scope: $pendingFolderWatchScope,
                    excludedSubdirectoryPaths: $pendingFolderWatchExcludedSubdirectoryPaths,
                    onCancel: { onAction(.cancelFolderWatch) },
                    onConfirm: { options in onAction(.confirmFolderWatch(options)) }
                )
            }
    }
}
