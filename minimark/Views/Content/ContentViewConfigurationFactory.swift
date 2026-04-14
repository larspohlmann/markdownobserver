import OSLog
import SwiftUI

/// Document surface configuration builders, file drop/pick handlers, and scroll sync wiring.
/// Split out from ContentView to keep that struct focused on layout and overlay composition.
extension ContentView {

    // MARK: - Document surface panes

    func documentSurfacePane(for surface: DocumentSurfaceRole) -> some View {
        DocumentSurfaceHost(
            configuration: documentSurfaceConfiguration(for: surface),
            fallbackMarkdown: readerStore.sourceMarkdown
        )
    }

    func documentSurfaceConfiguration(for surface: DocumentSurfaceRole) -> DocumentSurfaceConfiguration {
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
                changedRegionNavigationRequest: canNavigateChangedRegions ? changeNavigation.currentRequest : nil,
                scrollSyncRequest: splitScrollRequest(for: surface),
                tocScrollRequest: readerStore.tocScrollRequest,
                supportsInPlaceContentUpdates: true,
                overlayTopInset: overlayInsets.scrollTargetTopInset,
                reloadAnchorProgress: previewReloadAnchorProgress,
                minimumWidth: minimumSurfaceWidth,
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onAction: { action in
                    if handleSharedAction(action, for: .preview) { return }
                    switch action {
                    case .fatalCrash:
                        Self.logger.error("preview web surface hit fatal crash and fell back to native text")
                        previewMode = .nativeFallback
                    case .changedRegionNavigationResult(let index):
                        changeNavigation.handleNavigationResult(index: index)
                    case .retryFallback:
                        previewReloadToken += 1
                        previewMode = .web
                    default:
                        break
                    }
                }
            )
        case .source:
            return DocumentSurfaceConfiguration(
                role: surface,
                usesWebSurface: sourceMode == .web,
                htmlDocument: sourceHTMLCache.document,
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
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onAction: { action in
                    if handleSharedAction(action, for: .source) { return }
                    switch action {
                    case .fatalCrash:
                        Self.logger.error("source web surface hit fatal crash and fell back to plain text")
                        sourceMode = .plainTextFallback
                    case .postLoadStatus(let status):
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
                    case .sourceEdit(let markdown):
                        readerStore.updateSourceDraft(markdown)
                    case .retryFallback:
                        sourceReloadToken += 1
                        sourceMode = .web
                    default:
                        break
                    }
                }
            )
        }
    }

    // MARK: - Source document identity and HTML refresh

    var sourceDocumentIdentity: String? {
        guard let path = readerStore.fileURL?.standardizedFileURL.path else {
            return nil
        }

        return "\(path)|source"
    }

    func refreshSourceHTML() {
        sourceHTMLCache.refreshIfNeeded(
            markdown: readerStore.sourceEditorSeedMarkdown,
            settings: readerStore.currentSettings,
            isEditable: readerStore.isSourceEditing
        )
    }

    // MARK: - Shared action handling

    /// Handles action cases common to both preview and source surfaces.
    /// Returns `true` if the action was handled.
    func handleSharedAction(_ action: DocumentSurfaceAction, for surface: DocumentSurfaceRole) -> Bool {
        switch action {
        case .scrollSyncObservation(let observation):
            handleScrollSyncObservation(observation, from: surface)
            return true
        case .tocHeadingsExtracted(let headings):
            readerStore.updateTOCHeadings(headings)
            return true
        case .droppedFileURLs(let urls):
            handleDroppedFileURLs(urls)
            return true
        case .dropTargetedChange(let update):
            dropTargeting.update(for: surface, update: update)
            return true
        default:
            return false
        }
    }

    // MARK: - File drop and pick handlers

    func handleDroppedFileURLs(_ fileURLs: [URL]) {
        if let droppedFolderURL = ReaderFileRouting.firstDroppedDirectoryURL(from: fileURLs) {
            guard folderWatchState.activeFolderWatch == nil else {
                return
            }

            onAction(.requestFolderWatch(droppedFolderURL))
            return
        }

        let markdownURLs = ReaderFileRouting.supportedMarkdownFiles(from: fileURLs)
        guard !markdownURLs.isEmpty else {
            return
        }

        let slotStrategy: FileOpenRequest.SlotStrategy =
            readerStore.fileURL == nil ? .reuseEmptySlotForFirst : .alwaysAppend
        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: markdownURLs,
            origin: .manual,
            slotStrategy: slotStrategy
        )))
    }

    func handlePickedFileURLs(_ fileURLs: [URL]) {
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

        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: [markdownURLs[0]],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        )))

        let additionalMarkdownURLs = Array(markdownURLs.dropFirst())
        guard !additionalMarkdownURLs.isEmpty else {
            return
        }

        onAction(.requestFileOpen(FileOpenRequest(
            fileURLs: additionalMarkdownURLs,
            origin: .manual,
            slotStrategy: .alwaysAppend
        )))
    }

    func canAcceptDroppedFileURLs(_ fileURLs: [URL]) -> Bool {
        !ReaderFileRouting.containsLikelyDirectoryPath(in: fileURLs) || folderWatchState.activeFolderWatch == nil
    }

    // MARK: - Scroll sync wiring

    func splitScrollRequest(for surface: DocumentSurfaceRole) -> ScrollSyncRequest? {
        guard canSynchronizeSplitScroll else {
            return nil
        }

        return splitScrollCoordinator.request(for: surface)
    }

    var previewReloadAnchorProgress: Double? {
        guard canSynchronizeSplitScroll,
              readerStore.isSourceEditing else {
            return nil
        }

        return splitScrollCoordinator.latestObservedProgress(for: .source)
    }

    func handleScrollSyncObservation(
        _ observation: ScrollSyncObservation,
        from surface: DocumentSurfaceRole
    ) {
        splitScrollCoordinator.handleObservation(
            observation,
            from: surface,
            shouldSync: canSynchronizeSplitScroll
        )
    }
}
