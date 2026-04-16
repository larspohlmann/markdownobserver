import Foundation
import OSLog

enum PreviewMode {
    case web
    case nativeFallback
}

enum SourceMode {
    case web
    case plainTextFallback
}

@MainActor
@Observable
final class DocumentSurfaceViewModel {

    var previewMode: PreviewMode = .web
    var sourceMode: SourceMode = .web
    var previewReloadToken = 0
    var sourceReloadToken = 0

    let splitScrollCoordinator = SplitScrollCoordinator()
    var dropTargeting = DropTargetingCoordinator()
    var changeNavigation = ChangedRegionNavigationCoordinator()
    var sourceHTMLCache = SourceHTMLDocumentCache()

    private let renderedHTMLDocumentProvider: () -> String
    private let sourceMarkdownProvider: () -> String

    init(
        renderedHTMLDocument: String = "",
        sourceMarkdown: String = ""
    ) {
        self.renderedHTMLDocumentProvider = { renderedHTMLDocument }
        self.sourceMarkdownProvider = { sourceMarkdown }
    }

    init(
        renderedHTMLDocumentProvider: @escaping () -> String,
        sourceMarkdownProvider: @escaping () -> String
    ) {
        self.renderedHTMLDocumentProvider = renderedHTMLDocumentProvider
        self.sourceMarkdownProvider = sourceMarkdownProvider
    }

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

    func handleSurfaceAppear() {
        refreshSourceHTML(
            markdown: sourceMarkdownProvider(),
            settings: .default,
            isEditable: false
        )
        if previewMode == .nativeFallback, !renderedHTMLDocumentProvider().isEmpty {
            previewReloadToken += 1
            previewMode = .web
        }
        if sourceMode == .plainTextFallback, !sourceMarkdownProvider().isEmpty {
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

    func handleDocumentViewModeChange(_ mode: ReaderDocumentViewMode) {
        guard mode != .split else { return }
        splitScrollCoordinator.reset()
    }

    func refreshSourceHTML(
        markdown: String,
        settings: ReaderSettings,
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

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "DocumentSurfaceViewModel"
    )
}
