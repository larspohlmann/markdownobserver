import Foundation

/// Window-level controller that owns the `FolderWatchOpenBatcher` queue and dispatches
/// completed batches to the file open coordinator.
///
/// Distinct from `FolderWatchDispatcher` (per-document live event router) and
/// `FolderWatchOpenBatcher` (the underlying debouncing queue). This type ties the
/// queue to the window's host-window lifecycle: batches are held back until the
/// host window is attached, then dispatched in one shot followed by a presentation
/// refresh callback.
@MainActor
final class WindowFolderWatchOpenController {
    private let batcher = FolderWatchOpenBatcher()
    private let fileOpenCoordinator: FileOpenCoordinator
    private let isHostWindowAttached: () -> Bool
    private let onAfterFlush: () -> Void

    init(
        fileOpenCoordinator: FileOpenCoordinator,
        isHostWindowAttached: @escaping () -> Bool,
        onAfterFlush: @escaping () -> Void
    ) {
        self.fileOpenCoordinator = fileOpenCoordinator
        self.isHostWindowAttached = isHostWindowAttached
        self.onAfterFlush = onAfterFlush
    }

    var hasPendingEvents: Bool {
        batcher.hasPendingEvents
    }

    func enqueue(
        _ event: FolderWatchChangeEvent,
        folderWatchSession: FolderWatchSession?,
        origin: ReaderOpenOrigin
    ) {
        batcher.enqueue(
            event,
            folderWatchSession: folderWatchSession,
            origin: origin
        ) { [weak self] in
            self?.flush()
        }
    }

    func flush() {
        let batch = batcher.consumeBatchIfPossible(
            canFlushImmediately: isHostWindowAttached()
        ) { [weak self] in
            self?.flush()
        }
        guard let batch else { return }

        fileOpenCoordinator.open(FileOpenRequest(
            fileURLs: batch.fileURLs,
            origin: batch.openOrigin,
            folderWatchSession: batch.folderWatchSession,
            initialDiffBaselineMarkdownByURL: batch.initialDiffBaselineMarkdownByURL,
            slotStrategy: .reuseEmptySlotForFirst
        ))
        onAfterFlush()
    }
}
