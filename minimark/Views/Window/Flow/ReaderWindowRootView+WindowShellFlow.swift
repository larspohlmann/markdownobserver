import AppKit
import Foundation

extension ReaderWindowRootView {
    func applyWindowTitlePresentation() {
        let resolvedTitle = windowCoordinator.resolveWindowTitle(activeFolderWatch: sharedFolderWatchSession)
        effectiveWindowTitle = resolvedTitle
        hostWindow?.title = resolvedTitle
    }

    func enqueueFolderWatchOpen(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin
    ) {
        windowCoordinator.enqueueFolderWatchOpen(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin
        ) { [self] in
            flushQueuedFolderWatchOpens()
        }
    }

    func folderWatchChangeEvent(
        for fileURL: URL,
        initialDiffBaselineMarkdown: String?
    ) -> ReaderFolderWatchChangeEvent {
        ReaderFolderWatchChangeEvent(
            fileURL: fileURL,
            kind: initialDiffBaselineMarkdown == nil ? .added : .modified,
            previousMarkdown: initialDiffBaselineMarkdown
        )
    }

    func flushQueuedFolderWatchOpens() {
        let batch = windowCoordinator.consumeQueuedFolderWatchOpenBatchIfPossible(
            canFlushImmediately: hostWindow != nil
        ) { [self] in
            flushQueuedFolderWatchOpens()
        }

        guard let batch else {
            return
        }

        openSidebarDocumentsBurst(
            at: batch.fileURLs,
            origin: batch.openOrigin,
            folderWatchSession: batch.folderWatchSession,
            initialDiffBaselineMarkdownByURL: batch.initialDiffBaselineMarkdownByURL,
            preferEmptySelection: true
        )
    }

    func openSidebarDocumentsBurst(
        at fileURLs: [URL],
        origin: ReaderOpenOrigin = .manual,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdownByURL: [URL: String] = [:],
        preferEmptySelection: Bool
    ) {
        guard !fileURLs.isEmpty else {
            return
        }

        sidebarDocumentController.openDocumentsBurst(
            at: fileURLs,
            origin: origin,
            folderWatchSession: folderWatchSession,
            initialDiffBaselineMarkdownByURL: initialDiffBaselineMarkdownByURL,
            preferEmptySelection: preferEmptySelection
        )
        refreshWindowPresentation()
    }

    func refreshSharedFolderWatchState() {
        let state = windowCoordinator.sharedFolderWatchState()
        sharedFolderWatchSession = state.session
        canStopSharedFolderWatch = state.canStop
    }

    func refreshWindowPresentation() {
        refreshSharedFolderWatchState()
        applyWindowTitlePresentation()
    }

    func refreshWindowShellRegistrationAndTitle() {
        registerWindowIfNeeded()
        applyWindowTitlePresentation()
    }

    func refreshWindowShellState() {
        registerWindowIfNeeded()
        refreshWindowPresentation()
    }

    func registerWindowIfNeeded() {
        windowCoordinator.registerWindow(
            hostWindow,
            activeFolderWatch: sharedFolderWatchSession
        )
    }
}
