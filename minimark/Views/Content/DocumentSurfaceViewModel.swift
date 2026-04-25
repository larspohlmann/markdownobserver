import Foundation
import OSLog

@MainActor
@Observable
final class DocumentSurfaceViewModel {

    enum PreviewMode {
        case web
        case nativeFallback
    }

    enum SourceMode {
        case web
        case plainTextFallback
    }

    var previewMode: PreviewMode = .web
    var sourceMode: SourceMode = .web
    var previewReloadToken = 0
    var sourceReloadToken = 0

    let splitScrollCoordinator = SplitScrollCoordinator()
    var dropTargeting = DropTargetingCoordinator()
    var changeNavigation = ChangedRegionNavigationCoordinator()
    var sourceHTMLCache = SourceHTMLDocumentCache()

    init() {}

    func handleFileIdentityChange() {
        changeNavigation.reset()
        if previewMode == .nativeFallback {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback {
            sourceReloadToken += 1
            sourceMode = .web
        }
        dropTargeting.clearAll()
        splitScrollCoordinator.reset()
    }

    func handleSurfaceAppear(
        renderedHTMLDocument: String,
        sourceMarkdown: String
    ) {
        if previewMode == .nativeFallback, !renderedHTMLDocument.isEmpty {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback, !sourceMarkdown.isEmpty {
            sourceReloadToken += 1
            sourceMode = .web
        }
    }

    func handlePreviewModeChange(_ mode: PreviewMode) {
        guard mode == .nativeFallback else { return }
        dropTargeting.clear(for: .preview)
        splitScrollCoordinator.reset()
    }

    func handleSourceModeChange(_ mode: SourceMode) {
        guard mode == .plainTextFallback else { return }
        dropTargeting.clear(for: .source)
        splitScrollCoordinator.reset()
    }

    func handleDocumentViewModeChange(_ mode: DocumentViewMode) {
        guard mode != .split else { return }
        splitScrollCoordinator.reset()
    }

    func refreshSourceHTML(
        markdown: String,
        settings: Settings,
        isEditable: Bool
    ) {
        sourceHTMLCache.refreshIfNeeded(
            markdown: markdown,
            settings: settings,
            isEditable: isEditable
        )
    }

    func sourceDocumentIdentity(for fileURL: URL?) -> String? {
        guard let path = fileURL?.standardizedFileURL.path else { return nil }
        return "\(path)|source"
    }

    func handleSharedAction(
        _ action: DocumentSurfaceAction,
        for surface: DocumentSurfaceRole,
        documentViewMode: DocumentViewMode,
        onDroppedFileURLs: @escaping ([URL]) -> Void,
        onAction: @escaping (ContentViewAction) -> Void
    ) -> Bool {
        switch action {
        case .scrollSyncObservation(let observation):
            handleScrollSyncObservation(
                observation,
                from: surface,
                documentViewMode: documentViewMode
            )
            return true
        case .tocHeadingsExtracted(let headings):
            onAction(.updateTOCHeadings(headings))
            return true
        case .droppedFileURLs(let urls):
            onDroppedFileURLs(urls)
            return true
        case .dropTargetedChange(let update):
            dropTargeting.update(for: surface, update: update)
            return true
        default:
            return false
        }
    }

    func handleScrollSyncObservation(
        _ observation: ScrollSyncObservation,
        from surface: DocumentSurfaceRole,
        documentViewMode: DocumentViewMode
    ) {
        let shouldSync = canSynchronizeSplitScroll(documentViewMode: documentViewMode)
        splitScrollCoordinator.handleObservation(
            observation,
            from: surface,
            shouldSync: shouldSync
        )
    }

    func canNavigateChangedRegions(
        documentViewMode: DocumentViewMode,
        changedRegions: [ChangedRegion]
    ) -> Bool {
        documentViewMode != .source
            && previewMode == .web
            && !changedRegions.isEmpty
    }

    func canSynchronizeSplitScroll(
        documentViewMode: DocumentViewMode
    ) -> Bool {
        documentViewMode == .split
            && previewMode == .web
            && sourceMode == .web
    }

    func documentSurfaceConfiguration(
        for surface: DocumentSurfaceRole,
        fileURL: URL?,
        renderedHTMLDocument: String,
        documentViewMode: DocumentViewMode,
        changedRegions: [ChangedRegion],
        isSourceEditing: Bool,
        overlayTopInset: CGFloat,
        minimumSurfaceWidth: CGFloat?,
        tocScrollRequest: TOCScrollRequest?,
        canAcceptDroppedFileURLs: @escaping ([URL]) -> Bool,
        onSharedAction: @escaping (DocumentSurfaceAction, DocumentSurfaceRole) -> Bool,
        onAction: @escaping (ContentViewAction) -> Void
    ) -> DocumentSurfaceConfiguration {
        let canNavigateChangedRegions = canNavigateChangedRegions(
            documentViewMode: documentViewMode,
            changedRegions: changedRegions
        )
        let canSynchronizeSplitScroll = canSynchronizeSplitScroll(
            documentViewMode: documentViewMode
        )

        func splitScrollRequest(for surface: DocumentSurfaceRole) -> ScrollSyncRequest? {
            guard canSynchronizeSplitScroll else { return nil }
            return splitScrollCoordinator.request(for: surface)
        }

        let previewReloadAnchorProgress: Double? = {
            guard canSynchronizeSplitScroll, isSourceEditing else { return nil }
            return splitScrollCoordinator.latestObservedProgress(for: .source)
        }()

        switch surface {
        case .preview:
            return DocumentSurfaceConfiguration(
                role: surface,
                usesWebSurface: previewMode == .web,
                htmlDocument: renderedHTMLDocument,
                documentIdentity: fileURL?.standardizedFileURL.path,
                accessibilityIdentifier: "reader-preview",
                accessibilityValue: "file=\(fileURL?.lastPathComponent ?? "none")|regions=\(changedRegions.count)|mode=\(documentViewMode.rawValue)|surface=preview",
                reloadToken: previewReloadToken,
                diagnosticName: "reader-preview",
                postLoadStatusScript: nil,
                changedRegionNavigationRequest: canNavigateChangedRegions ? changeNavigation.currentRequest : nil,
                scrollSyncRequest: splitScrollRequest(for: surface),
                tocScrollRequest: tocScrollRequest,
                supportsInPlaceContentUpdates: true,
                overlayTopInset: overlayTopInset,
                reloadAnchorProgress: previewReloadAnchorProgress,
                minimumWidth: minimumSurfaceWidth,
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onAction: { action in
                    if onSharedAction(action, .preview) { return }
                    switch action {
                    case .fatalCrash:
                        Self.logger.error("preview web surface hit fatal crash and fell back to native text")
                        self.previewMode = .nativeFallback
                    case .changedRegionNavigationResult(let index):
                        self.changeNavigation.handleNavigationResult(index: index)
                    case .retryFallback:
                        self.previewReloadToken += 1
                        self.previewMode = .web
                    case .openLinkedFile(let url):
                        onAction(.requestFileOpen(FileOpenRequest(
                            fileURLs: [url],
                            origin: .manual,
                            slotStrategy: .alwaysAppend
                        )))
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
                documentIdentity: sourceDocumentIdentity(for: fileURL),
                accessibilityIdentifier: "reader-source",
                accessibilityValue: "file=\(fileURL?.lastPathComponent ?? "none")|mode=\(documentViewMode.rawValue)|surface=source",
                reloadToken: sourceReloadToken,
                diagnosticName: "reader-source",
                postLoadStatusScript: "window.__minimarkSourceBootstrapStatus || null",
                changedRegionNavigationRequest: nil,
                scrollSyncRequest: splitScrollRequest(for: surface),
                tocScrollRequest: tocScrollRequest,
                supportsInPlaceContentUpdates: false,
                overlayTopInset: overlayTopInset,
                reloadAnchorProgress: nil,
                minimumWidth: minimumSurfaceWidth,
                canAcceptDroppedFileURLs: canAcceptDroppedFileURLs,
                onAction: { action in
                    if onSharedAction(action, .source) { return }
                    switch action {
                    case .fatalCrash:
                        Self.logger.error("source web surface hit fatal crash and fell back to plain text")
                        self.sourceMode = .plainTextFallback
                    case .postLoadStatus(let status):
                        guard let status else {
                            Self.logger.error("source post-load status probe returned no status")
                            self.sourceMode = .plainTextFallback
                            return
                        }
                        guard status == "ready" else {
                            Self.logger.error("source bootstrap status was \(status, privacy: .public); falling back to plain text")
                            self.sourceMode = .plainTextFallback
                            return
                        }
                        Self.logger.debug("source bootstrap completed successfully")
                    case .sourceEdit(let markdown):
                        onAction(.updateSourceDraft(markdown))
                    case .retryFallback:
                        self.sourceReloadToken += 1
                        self.sourceMode = .web
                    default:
                        break
                    }
                }
            )
        }
    }

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "DocumentSurfaceViewModel"
    )
}
