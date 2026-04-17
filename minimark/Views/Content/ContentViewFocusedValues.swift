import SwiftUI

struct ContentViewFocusedValues: ViewModifier {
    let documentStore: DocumentStore
    let folderWatchState: ContentViewFolderWatchState
    let onAction: (ContentViewAction) -> Void
    let changedRegionNavigation: ChangedRegionNavigationAction

    @Environment(FolderWatchFlowController.self) private var folderWatchFlow

    private var document: DocumentController { documentStore.document }
    private var sourceEditing: SourceEditingController { documentStore.sourceEditingController }
    private var toc: TOCController { documentStore.toc }

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
        @Bindable var folderWatchFlow = folderWatchFlow
        return content
            .focusedValue(
                \.openDocumentInCurrentWindow,
                OpenDocumentInCurrentWindowAction { fileURL in
                    let normalizedURL = FileRouting.normalizedFileURL(fileURL)
                    let currentURL = document.fileURL.map(FileRouting.normalizedFileURL)
                    if sourceEditing.hasUnsavedDraftChanges, currentURL != normalizedURL {
                        onAction(.presentError(AppError.unsavedDraftRequiresResolution))
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
                \.openDocument,
                OpenDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedValue(
                \.openAdditionalDocument,
                OpenAdditionalDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedValue(
                \.watchFolder,
                WatchFolderAction { folderURL in
                    onAction(.requestFolderWatch(folderURL))
                }
            )
            .focusedValue(
                \.startRecentFolderWatch,
                StartRecentFolderWatchAction { entry in
                    onAction(.startRecentFolderWatch(entry))
                }
            )
            .focusedValue(
                \.stopFolderWatch,
                StopFolderWatchAction {
                    guard folderWatchState.canStopFolderWatch else {
                        return
                    }
                    onAction(.stopFolderWatch)
                }
            )
            .focusedValue(
                \.hasActiveFolderWatch,
                folderWatchState.canStopFolderWatch
            )
            .focusedValue(
                \.documentViewModeContext,
                DocumentViewModeContext(
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
                \.sourceEditingContext,
                SourceEditingContext(
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
                \.changedRegionNavigation,
                changedRegionNavigation
            )
            .focusedValue(
                \.toggleTOC,
                ToggleTOCAction(
                    canToggle: !toc.headings.isEmpty,
                    toggle: { toc.toggle() }
                )
            )
            .onChange(of: folderWatchFlow.isFolderWatchOptionsPresented) { _, isPresented in
                guard !isPresented else { return }
                onAction(.cancelFolderWatch)
            }
            .sheet(isPresented: $folderWatchFlow.isFolderWatchOptionsPresented) {
                FolderWatchOptionsSheet(
                    folderURL: folderWatchState.pendingFolderWatchURL,
                    openMode: folderWatchFlow.pendingOpenModeBinding,
                    scope: folderWatchFlow.pendingScopeBinding,
                    excludedSubdirectoryPaths: folderWatchFlow.pendingExcludedSubdirectoryPathsBinding,
                    onCancel: { onAction(.cancelFolderWatch) },
                    onConfirm: { options in onAction(.confirmFolderWatch(options)) }
                )
            }
    }
}
