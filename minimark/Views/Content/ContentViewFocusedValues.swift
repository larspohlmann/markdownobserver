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

    private var pendingOpenModeBinding: Binding<FolderWatchOpenMode> {
        Binding(
            get: { folderWatchFlow.pendingFolderWatchRequest?.options.openMode ?? FolderWatchOptions.default.openMode },
            set: { newValue in
                folderWatchFlow.updatePendingRequest { $0.options.openMode = newValue }
            }
        )
    }

    private var pendingScopeBinding: Binding<FolderWatchScope> {
        Binding(
            get: { folderWatchFlow.pendingFolderWatchRequest?.options.scope ?? FolderWatchOptions.default.scope },
            set: { newValue in
                folderWatchFlow.updatePendingRequest { $0.options.scope = newValue }
            }
        )
    }

    private var pendingExcludedSubdirectoryPathsBinding: Binding<[String]> {
        Binding(
            get: { folderWatchFlow.pendingFolderWatchRequest?.options.excludedSubdirectoryPaths ?? [] },
            set: { newValue in
                folderWatchFlow.updatePendingRequest { $0.options.excludedSubdirectoryPaths = newValue }
            }
        )
    }

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
        // Scene-scoped, not view-focused: commands need the values whenever this
        // window is key, even when no descendant has keyboard focus. `focusedValue`
        // would require a focused view in the chain, which leaves the menu items
        // disabled on cold launch (issue #384).
        @Bindable var folderWatchFlow = folderWatchFlow
        return content
            .focusedSceneValue(
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
            .focusedSceneValue(
                \.openDocument,
                OpenDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedSceneValue(
                \.openAdditionalDocument,
                OpenAdditionalDocumentAction { fileURL in openOrAppendDocument(fileURL) }
            )
            .focusedSceneValue(
                \.watchFolder,
                WatchFolderAction { folderURL in
                    onAction(.requestFolderWatch(folderURL))
                }
            )
            .focusedSceneValue(
                \.startRecentFolderWatch,
                StartRecentFolderWatchAction { entry in
                    onAction(.startRecentFolderWatch(entry))
                }
            )
            .focusedSceneValue(
                \.stopFolderWatch,
                StopFolderWatchAction {
                    guard folderWatchState.canStopFolderWatch else {
                        return
                    }
                    onAction(.stopFolderWatch)
                }
            )
            .focusedSceneValue(
                \.hasActiveFolderWatch,
                folderWatchState.canStopFolderWatch
            )
            .focusedSceneValue(
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
            .focusedSceneValue(
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
            .focusedSceneValue(
                \.changedRegionNavigation,
                changedRegionNavigation
            )
            .focusedSceneValue(
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
                    openMode: pendingOpenModeBinding,
                    scope: pendingScopeBinding,
                    excludedSubdirectoryPaths: pendingExcludedSubdirectoryPathsBinding,
                    onCancel: { onAction(.cancelFolderWatch) },
                    onConfirm: { options in onAction(.confirmFolderWatch(options)) }
                )
            }
    }
}
