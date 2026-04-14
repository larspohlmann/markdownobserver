import SwiftUI

struct ContentViewFocusedValues: ViewModifier {
    let readerStore: ReaderStore
    let folderWatchState: ContentViewFolderWatchState
    let onAction: (ContentViewAction) -> Void
    let canNavigateChangedRegions: Bool
    let onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void
    @Binding var isFolderWatchOptionsPresented: Bool
    @Binding var pendingFolderWatchOpenMode: ReaderFolderWatchOpenMode
    @Binding var pendingFolderWatchScope: ReaderFolderWatchScope
    @Binding var pendingFolderWatchExcludedSubdirectoryPaths: [String]

    private func openOrAppendDocument(_ fileURL: URL) {
        let strategy: FileOpenRequest.SlotStrategy =
            readerStore.fileURL == nil ? .replaceSelectedSlot : .alwaysAppend
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
                    let currentURL = readerStore.fileURL.map(ReaderFileRouting.normalizedFileURL)
                    if readerStore.hasUnsavedDraftChanges, currentURL != normalizedURL {
                        readerStore.presentError(ReaderError.unsavedDraftRequiresResolution)
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
                    navigate: onNavigateChangedRegion
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
