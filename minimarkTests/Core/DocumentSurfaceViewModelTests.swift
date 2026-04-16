import Foundation
import Testing
@testable import minimark

@Suite
struct DocumentSurfaceViewModelModeTests {

    @MainActor
    private func makeViewModel() -> DocumentSurfaceViewModel {
        DocumentSurfaceViewModel()
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
        let vm = makeViewModel()
        vm.previewMode = .nativeFallback
        vm.handleSurfaceAppear(renderedHTMLDocument: "<html></html>", sourceMarkdown: "hello")
        #expect(vm.previewMode == .web)
        #expect(vm.previewReloadToken == 1)
    }

    @Test @MainActor func handleSurfaceAppear_doesNotRestorePreviewWhenContentEmpty() {
        let vm = makeViewModel()
        vm.previewMode = .nativeFallback
        vm.handleSurfaceAppear(renderedHTMLDocument: "", sourceMarkdown: "hello")
        #expect(vm.previewMode == .nativeFallback)
        #expect(vm.previewReloadToken == 0)
    }

    @Test @MainActor func handleSurfaceAppear_doesNotRestoreSourceWhenContentEmpty() {
        let vm = makeViewModel()
        vm.sourceMode = .plainTextFallback
        vm.handleSurfaceAppear(renderedHTMLDocument: "<html></html>", sourceMarkdown: "")
        #expect(vm.sourceMode == .plainTextFallback)
        #expect(vm.sourceReloadToken == 0)
    }

    @Test @MainActor func handleSurfaceAppear_restoresSourceToWebWhenContentAvailable() {
        let vm = makeViewModel()
        vm.sourceMode = .plainTextFallback
        vm.handleSurfaceAppear(renderedHTMLDocument: "<html></html>", sourceMarkdown: "hello")
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
        let vm = DocumentSurfaceViewModel()
        vm.refreshSourceHTML(
            markdown: "# Hello",
            settings: .default,
            isEditable: false
        )
        #expect(!vm.sourceHTMLCache.document.isEmpty)
    }

    @Test @MainActor func refreshSourceHTML_skipsRefreshWhenInputsUnchanged() {
        let vm = DocumentSurfaceViewModel()
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        let first = vm.sourceHTMLCache.document
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        #expect(vm.sourceHTMLCache.document == first)
    }

    @Test @MainActor func refreshSourceHTML_refreshesWhenMarkdownChanges() {
        let vm = DocumentSurfaceViewModel()
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        let first = vm.sourceHTMLCache.document
        vm.refreshSourceHTML(markdown: "# World", settings: .default, isEditable: false)
        #expect(vm.sourceHTMLCache.document != first)
    }

    @Test @MainActor func sourceDocumentIdentity_returnsPathPipeSource() {
        let vm = DocumentSurfaceViewModel()
        let url = URL(fileURLWithPath: "/Users/test/doc.md")
        #expect(vm.sourceDocumentIdentity(for: url) == "/Users/test/doc.md|source")
    }

    @Test @MainActor func sourceDocumentIdentity_returnsNilForNilURL() {
        let vm = DocumentSurfaceViewModel()
        #expect(vm.sourceDocumentIdentity(for: nil) == nil)
    }
}

@Suite
struct DocumentSurfaceViewModelConfigurationTests {

    @Test @MainActor func previewConfiguration_usesWebWhenModeIsWeb() {
        let vm = DocumentSurfaceViewModel()
        let config = vm.documentSurfaceConfiguration(
            for: .preview,
            fileURL: nil,
            renderedHTMLDocument: "<html></html>",
            documentViewMode: .preview,
            changedRegions: [],
            isSourceEditing: false,
            overlayTopInset: 0,
            minimumSurfaceWidth: nil,
            tocScrollRequest: nil,
            canAcceptDroppedFileURLs: { _ in true },
            onSharedAction: { _, _ in false },
            onAction: { _ in }
        )
        #expect(config.usesWebSurface == true)
        #expect(config.role == .preview)
    }

    @Test @MainActor func previewConfiguration_usesFallbackWhenModeIsNativeFallback() {
        let vm = DocumentSurfaceViewModel()
        vm.previewMode = .nativeFallback
        let config = vm.documentSurfaceConfiguration(
            for: .preview,
            fileURL: nil,
            renderedHTMLDocument: "",
            documentViewMode: .preview,
            changedRegions: [],
            isSourceEditing: false,
            overlayTopInset: 0,
            minimumSurfaceWidth: nil,
            tocScrollRequest: nil,
            canAcceptDroppedFileURLs: { _ in true },
            onSharedAction: { _, _ in false },
            onAction: { _ in }
        )
        #expect(config.usesWebSurface == false)
    }

    @Test @MainActor func sourceConfiguration_usesWebWhenModeIsWeb() {
        let vm = DocumentSurfaceViewModel()
        vm.refreshSourceHTML(markdown: "# Hello", settings: .default, isEditable: false)
        let config = vm.documentSurfaceConfiguration(
            for: .source,
            fileURL: nil,
            renderedHTMLDocument: "",
            documentViewMode: .source,
            changedRegions: [],
            isSourceEditing: false,
            overlayTopInset: 0,
            minimumSurfaceWidth: nil,
            tocScrollRequest: nil,
            canAcceptDroppedFileURLs: { _ in true },
            onSharedAction: { _, _ in false },
            onAction: { _ in }
        )
        #expect(config.usesWebSurface == true)
        #expect(config.role == .source)
    }

    @Test @MainActor func sourceConfiguration_usesFallbackWhenModeIsPlainTextFallback() {
        let vm = DocumentSurfaceViewModel()
        vm.sourceMode = .plainTextFallback
        let config = vm.documentSurfaceConfiguration(
            for: .source,
            fileURL: nil,
            renderedHTMLDocument: "",
            documentViewMode: .source,
            changedRegions: [],
            isSourceEditing: false,
            overlayTopInset: 0,
            minimumSurfaceWidth: nil,
            tocScrollRequest: nil,
            canAcceptDroppedFileURLs: { _ in true },
            onSharedAction: { _, _ in false },
            onAction: { _ in }
        )
        #expect(config.usesWebSurface == false)
    }

    @Test @MainActor func previewConfiguration_includesChangedRegionNavWhenApplicable() {
        let vm = DocumentSurfaceViewModel()
        vm.changeNavigation.requestNavigation(.next)
        let config = vm.documentSurfaceConfiguration(
            for: .preview,
            fileURL: nil,
            renderedHTMLDocument: "<html></html>",
            documentViewMode: .preview,
            changedRegions: [ChangedRegion(blockIndex: 0, lineRange: 1...2)],
            isSourceEditing: false,
            overlayTopInset: 0,
            minimumSurfaceWidth: nil,
            tocScrollRequest: nil,
            canAcceptDroppedFileURLs: { _ in true },
            onSharedAction: { _, _ in false },
            onAction: { _ in }
        )
        #expect(config.changedRegionNavigationRequest != nil)
    }
}

@Suite
struct DocumentSurfaceViewModelSharedActionsTests {

    @Test @MainActor func handleSharedAction_scrollSyncObservation_forwardsToCoordinator() {
        let vm = DocumentSurfaceViewModel()
        let handled = vm.handleSharedAction(
            .scrollSyncObservation(ScrollSyncObservation(progress: 0.5, isProgrammatic: false)),
            for: .preview,
            documentViewMode: .split,
            onDroppedFileURLs: { _ in },
            onAction: { _ in }
        )
        #expect(handled == true)
    }

    @Test @MainActor func handleSharedAction_dropTargetingUpdate_updatesDropTargeting() {
        let vm = DocumentSurfaceViewModel()
        let handled = vm.handleSharedAction(
            .dropTargetedChange(DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)),
            for: .preview,
            documentViewMode: .preview,
            onDroppedFileURLs: { _ in },
            onAction: { _ in }
        )
        #expect(handled == true)
        #expect(vm.dropTargeting.isDragTargeted)
    }

    @Test @MainActor func handleSharedAction_droppedFileURLs_callsHandler() {
        let vm = DocumentSurfaceViewModel()
        var receivedURLs: [URL] = []
        let handled = vm.handleSharedAction(
            .droppedFileURLs([URL(fileURLWithPath: "/test.md")]),
            for: .preview,
            documentViewMode: .preview,
            onDroppedFileURLs: { urls in receivedURLs = urls },
            onAction: { _ in }
        )
        #expect(handled == true)
        #expect(receivedURLs.count == 1)
    }

    @Test @MainActor func handleSharedAction_unhandledAction_returnsFalse() {
        let vm = DocumentSurfaceViewModel()
        let handled = vm.handleSharedAction(
            .fatalCrash,
            for: .preview,
            documentViewMode: .preview,
            onDroppedFileURLs: { _ in },
            onAction: { _ in }
        )
        #expect(handled == false)
    }

    @Test @MainActor func canNavigateChangedRegions_trueWhenNotSourceModeWebWithRegions() {
        let vm = DocumentSurfaceViewModel()
        #expect(vm.canNavigateChangedRegions(
            documentViewMode: .preview,
            changedRegions: [ChangedRegion(blockIndex: 0, lineRange: 1...2)]
        ) == true)
    }

    @Test @MainActor func canNavigateChangedRegions_falseInSourceMode() {
        let vm = DocumentSurfaceViewModel()
        #expect(vm.canNavigateChangedRegions(
            documentViewMode: .source,
            changedRegions: [ChangedRegion(blockIndex: 0, lineRange: 1...2)]
        ) == false)
    }

    @Test @MainActor func canSynchronizeSplitScroll_trueInSplitWithBothWeb() {
        let vm = DocumentSurfaceViewModel()
        #expect(vm.canSynchronizeSplitScroll(documentViewMode: .split) == true)
    }

    @Test @MainActor func canSynchronizeSplitScroll_falseWhenSourceIsFallback() {
        let vm = DocumentSurfaceViewModel()
        vm.sourceMode = .plainTextFallback
        #expect(vm.canSynchronizeSplitScroll(documentViewMode: .split) == false)
    }

    @Test @MainActor func scrollSyncObservation_invalidatesObservers() {
        let vm = DocumentSurfaceViewModel()

        var invalidationFired = false
        withObservationTracking {
            _ = vm.documentSurfaceConfiguration(
                for: .preview,
                fileURL: nil,
                renderedHTMLDocument: "",
                documentViewMode: .split,
                changedRegions: [],
                isSourceEditing: false,
                overlayTopInset: 0,
                minimumSurfaceWidth: nil,
                tocScrollRequest: nil,
                canAcceptDroppedFileURLs: { _ in true },
                onSharedAction: { _, _ in false },
                onAction: { _ in }
            )
        } onChange: {
            invalidationFired = true
        }

        vm.handleScrollSyncObservation(
            ScrollSyncObservation(progress: 0.5, isProgrammatic: false),
            from: .source,
            documentViewMode: .split
        )

        #expect(invalidationFired, "Split-scroll coordinator mutation must invalidate the view model's observers so ContentView re-evaluates and the fresh scrollSyncRequest reaches MarkdownWebView.")
    }
}
