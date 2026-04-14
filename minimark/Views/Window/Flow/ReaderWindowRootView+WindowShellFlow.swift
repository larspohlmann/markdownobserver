import AppKit
import Foundation

extension ReaderWindowRootView {
    func applyWindowTitlePresentation() {
        let resolvedTitle = windowCoordinator.resolveWindowTitle(activeFolderWatch: folderWatchFlowController.sharedFolderWatchSession)
        let mutation = ReaderWindowTitleFormatter.mutation(
            resolvedTitle: resolvedTitle,
            currentEffectiveTitle: windowCoordinator.effectiveWindowTitle,
            currentHostWindowTitle: windowCoordinator.hostWindow?.title
        )
        if mutation.shouldUpdateEffectiveTitle {
            windowCoordinator.effectiveWindowTitle = mutation.effectiveTitle
        }
        if mutation.shouldWriteHostWindowTitle {
            windowCoordinator.hostWindow?.title = mutation.effectiveTitle
        }
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
            canFlushImmediately: windowCoordinator.hostWindow != nil
        ) { [self] in
            flushQueuedFolderWatchOpens()
        }

        guard let batch else {
            return
        }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: batch.fileURLs,
            origin: batch.openOrigin,
            folderWatchSession: batch.folderWatchSession,
            initialDiffBaselineMarkdownByURL: batch.initialDiffBaselineMarkdownByURL,
            slotStrategy: .reuseEmptySlotForFirst
        ))
        refreshWindowPresentation()
    }


    func refreshSharedFolderWatchState() {
        folderWatchFlowController.refreshSharedState()
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
            windowCoordinator.hostWindow,
            activeFolderWatch: folderWatchFlowController.sharedFolderWatchSession
        )
    }
}
