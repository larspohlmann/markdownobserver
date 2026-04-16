import Foundation
import Testing
@testable import minimark

@Suite
struct DocumentSurfaceViewModelModeTests {

    @MainActor
    private func makeViewModel(
        renderedHTMLDocument: String = "",
        sourceMarkdown: String = ""
    ) -> DocumentSurfaceViewModel {
        DocumentSurfaceViewModel(
            renderedHTMLDocument: renderedHTMLDocument,
            sourceMarkdown: sourceMarkdown
        )
    }

    @Test @MainActor func initialModesAreWeb() {
        let vm = makeViewModel()
        #expect(vm.previewMode == .web)
        #expect(vm.sourceMode == .web)
    }

    @Test @MainActor func initialReloadTokensAreZero() {
        let vm = makeViewModel()
        #expect(vm.previewReloadToken == 0)
        #expect(vm.sourceReloadToken == 0)
    }

    @Test @MainActor func handleFileIdentityChange_resetsModesToWeb() {
        let vm = makeViewModel()
        vm.previewMode = .nativeFallback
        vm.sourceMode = .plainTextFallback
        vm.handleFileIdentityChange()
        #expect(vm.previewMode == .web)
        #expect(vm.sourceMode == .web)
    }

    @Test @MainActor func handleFileIdentityChange_incrementsReloadTokensOnFallback() {
        let vm = makeViewModel()
        vm.previewMode = .nativeFallback
        vm.sourceMode = .plainTextFallback
        vm.handleFileIdentityChange()
        #expect(vm.previewReloadToken == 1)
        #expect(vm.sourceReloadToken == 1)
    }

    @Test @MainActor func handleFileIdentityChange_doesNotIncrementTokensWhenAlreadyWeb() {
        let vm = makeViewModel()
        vm.handleFileIdentityChange()
        #expect(vm.previewReloadToken == 0)
        #expect(vm.sourceReloadToken == 0)
    }

    @Test @MainActor func handleFileIdentityChange_resetsScrollCoordinator() {
        let vm = makeViewModel()
        let coordinator = vm.splitScrollCoordinator
        coordinator.handleObservation(
            ScrollSyncObservation(progress: 0.5, isProgrammatic: false),
            from: .preview,
            shouldSync: true
        )
        vm.handleFileIdentityChange()
        #expect(coordinator.request(for: .preview) == nil)
    }

    @Test @MainActor func handleFileIdentityChange_resetsDropTargeting() {
        let vm = makeViewModel()
        vm.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        vm.handleFileIdentityChange()
        #expect(!vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handleFileIdentityChange_resetsChangeNavigation() {
        let vm = makeViewModel()
        vm.changeNavigation.requestNavigation(.next)
        vm.changeNavigation.handleNavigationResult(index: 2)
        vm.handleFileIdentityChange()
        #expect(vm.changeNavigation.currentIndex == nil)
        #expect(vm.changeNavigation.currentRequest == nil)
    }

    @Test @MainActor func handleSurfaceAppear_restoresPreviewToWebWhenContentAvailable() {
        let vm = makeViewModel(renderedHTMLDocument: "<html></html>", sourceMarkdown: "hello")
        vm.previewMode = .nativeFallback
        vm.handleSurfaceAppear()
        #expect(vm.previewMode == .web)
        #expect(vm.previewReloadToken == 1)
    }

    @Test @MainActor func handleSurfaceAppear_doesNotRestorePreviewWhenContentEmpty() {
        let vm = makeViewModel(renderedHTMLDocument: "", sourceMarkdown: "hello")
        vm.previewMode = .nativeFallback
        vm.handleSurfaceAppear()
        #expect(vm.previewMode == .nativeFallback)
        #expect(vm.previewReloadToken == 0)
    }

    @Test @MainActor func handleSurfaceAppear_doesNotRestoreSourceWhenContentEmpty() {
        let vm = makeViewModel(renderedHTMLDocument: "<html></html>", sourceMarkdown: "")
        vm.sourceMode = .plainTextFallback
        vm.handleSurfaceAppear()
        #expect(vm.sourceMode == .plainTextFallback)
        #expect(vm.sourceReloadToken == 0)
    }

    @Test @MainActor func handleSurfaceAppear_restoresSourceToWebWhenContentAvailable() {
        let vm = makeViewModel(renderedHTMLDocument: "<html></html>", sourceMarkdown: "hello")
        vm.sourceMode = .plainTextFallback
        vm.handleSurfaceAppear()
        #expect(vm.sourceMode == .web)
        #expect(vm.sourceReloadToken == 1)
    }

    @Test @MainActor func handlePreviewModeChangeOnFallback_clearsDropAndScroll() {
        let vm = makeViewModel()
        vm.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        vm.handlePreviewModeChange(.nativeFallback)
        #expect(!vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handlePreviewModeChangeOnWeb_doesNothing() {
        let vm = makeViewModel()
        vm.dropTargeting.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        vm.handlePreviewModeChange(.web)
        #expect(vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handleSourceModeChangeOnWeb_doesNothing() {
        let vm = makeViewModel()
        vm.dropTargeting.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        vm.handleSourceModeChange(.web)
        #expect(vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handleSourceModeChangeOnFallback_clearsDropAndScroll() {
        let vm = makeViewModel()
        vm.dropTargeting.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        vm.handleSourceModeChange(.plainTextFallback)
        #expect(!vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handleDocumentViewModeChange_leavingSplit_resetsScroll() {
        let vm = makeViewModel()
        vm.splitScrollCoordinator.handleObservation(
            ScrollSyncObservation(progress: 0.5, isProgrammatic: false),
            from: .preview,
            shouldSync: true
        )
        vm.handleDocumentViewModeChange(.preview)
        #expect(vm.splitScrollCoordinator.request(for: .preview) == nil)
    }

    @Test @MainActor func handleDocumentViewModeChange_stayingSplit_doesNothing() {
        let vm = makeViewModel()
        vm.splitScrollCoordinator.handleObservation(
            ScrollSyncObservation(progress: 0.5, isProgrammatic: false),
            from: .preview,
            shouldSync: true
        )
        vm.handleDocumentViewModeChange(.split)
        #expect(vm.splitScrollCoordinator.request(for: .source) != nil)
    }
}

@Suite
struct DocumentSurfaceViewModelSourceHTMLTests {

    @Test @MainActor func refreshSourceHTML_producesNonEmptyDocument() {
        let vm = DocumentSurfaceViewModel(
            renderedHTMLDocumentProvider: { "" },
            sourceMarkdownProvider: { "# Hello" }
        )
        vm.refreshSourceHTML(
            markdown: "# Hello",
            settings: .default,
            isEditable: false
        )
        #expect(!vm.sourceHTMLCache.document.isEmpty)
    }

    @Test @MainActor func refreshSourceHTML_skipsRefreshWhenInputsUnchanged() {
        let vm = DocumentSurfaceViewModel(
            renderedHTMLDocumentProvider: { "" },
            sourceMarkdownProvider: { "# Hello" }
        )
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        let first = vm.sourceHTMLCache.document
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        #expect(vm.sourceHTMLCache.document == first)
    }

    @Test @MainActor func refreshSourceHTML_refreshesWhenMarkdownChanges() {
        let vm = DocumentSurfaceViewModel(
            renderedHTMLDocumentProvider: { "" },
            sourceMarkdownProvider: { "# Hello" }
        )
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        let first = vm.sourceHTMLCache.document
        vm.refreshSourceHTML(markdown: "# World", settings: .default, isEditable: false)
        #expect(vm.sourceHTMLCache.document != first)
    }

    @Test @MainActor func sourceDocumentIdentity_returnsPathPipeSource() {
        let vm = DocumentSurfaceViewModel(
            renderedHTMLDocumentProvider: { "" },
            sourceMarkdownProvider: { "" }
        )
        let url = URL(fileURLWithPath: "/Users/test/doc.md")
        #expect(vm.sourceDocumentIdentity(for: url) == "/Users/test/doc.md|source")
    }

    @Test @MainActor func sourceDocumentIdentity_returnsNilForNilURL() {
        let vm = DocumentSurfaceViewModel(
            renderedHTMLDocumentProvider: { "" },
            sourceMarkdownProvider: { "" }
        )
        #expect(vm.sourceDocumentIdentity(for: nil) == nil)
    }
}
