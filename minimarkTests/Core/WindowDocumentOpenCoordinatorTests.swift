import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct WindowDocumentOpenCoordinatorTests {

    @MainActor
    private func makeCoordinator(
        folderWatchSession: FolderWatchSession? = nil,
        onAfterTitle: @escaping () -> Void = {},
        onAfterRefresh: @escaping () -> Void = {},
        onPrepareRecentFolderWatch: @escaping (URL, FolderWatchOptions) -> Void = { _, _ in }
    ) throws -> (WindowDocumentOpenCoordinator, WindowFolderWatchOpenController, ReaderSidebarControllerTestHarness) {
        ReaderWindowRegistry.shared.resetForTesting()
        let harness = try ReaderSidebarControllerTestHarness()
        let folderWatchOpen = WindowFolderWatchOpenController(
            fileOpenCoordinator: harness.controller.fileOpenCoordinator,
            isHostWindowAttached: { false },
            onAfterFlush: {}
        )
        let coordinator = WindowDocumentOpenCoordinator(
            fileOpenCoordinator: harness.controller.fileOpenCoordinator,
            folderWatchOpen: folderWatchOpen,
            sidebarDocumentController: harness.controller,
            settingsStore: harness.settingsStore,
            folderWatchSessionProvider: { folderWatchSession },
            applyTitlePresentation: onAfterTitle,
            refreshWindowPresentation: onAfterRefresh,
            prepareRecentFolderWatch: onPrepareRecentFolderWatch
        )
        return (coordinator, folderWatchOpen, harness)
    }

    @Test @MainActor
    func openIncomingURLIgnoresNonMarkdown() throws {
        var titleCalls = 0
        let (coordinator, _, harness) = try makeCoordinator(onAfterTitle: { titleCalls += 1 })
        defer { harness.cleanup() }

        coordinator.openIncomingURL(URL(fileURLWithPath: "/tmp/not-markdown.txt"))

        #expect(titleCalls == 0)
    }

    @Test @MainActor
    func openIncomingURLOpensMarkdownAndAppliesTitle() throws {
        var titleCalls = 0
        let (coordinator, _, harness) = try makeCoordinator(onAfterTitle: { titleCalls += 1 })
        defer { harness.cleanup() }

        coordinator.openIncomingURL(harness.primaryFileURL)

        #expect(titleCalls == 1)
    }

    @Test @MainActor
    func openAdditionalDocumentWithFolderWatchSessionEnqueuesOnBatcher() throws {
        let session = FolderWatchSession(
            folderURL: URL(fileURLWithPath: "/tmp/watch", isDirectory: true),
            options: FolderWatchOptions.default,
            startedAt: Date()
        )
        let (coordinator, folderWatchOpen, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        coordinator.openAdditionalDocumentInCurrentWindow(
            harness.primaryFileURL,
            folderWatchSession: session,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# baseline"
        )

        #expect(folderWatchOpen.hasPendingEvents)
    }

    @Test @MainActor
    func openFileRequestRefreshesWindowPresentation() throws {
        var refreshCalls = 0
        let (coordinator, _, harness) = try makeCoordinator(onAfterRefresh: { refreshCalls += 1 })
        defer { harness.cleanup() }

        coordinator.openFileRequest(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        #expect(refreshCalls == 1)
    }
}
