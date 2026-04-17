import Combine
import Foundation

struct FolderWatchOpenBatch: Equatable, Sendable {
    let fileURLs: [URL]
    let initialDiffBaselineMarkdownByURL: [URL: String]
    let folderWatchSession: ReaderFolderWatchSession?
    let openOrigin: ReaderOpenOrigin
}

@MainActor
final class FolderWatchOpenBatcher: ObservableObject {
    private var queuedEvents: [ReaderFolderWatchChangeEvent] = []
    private var queuedFolderWatchSession: ReaderFolderWatchSession?
    private var queuedOpenOrigin: ReaderOpenOrigin = .manual
    private var flushTask: Task<Void, Never>?
    private var flushRetryCount = 0

    deinit {
        flushTask?.cancel()
    }

    var hasPendingEvents: Bool {
        !queuedEvents.isEmpty
    }

    func enqueue(
        _ event: ReaderFolderWatchChangeEvent,
        folderWatchSession: ReaderFolderWatchSession?,
        origin: ReaderOpenOrigin,
        onFlushRequested: @escaping @MainActor () -> Void
    ) {
        if let existingIndex = queuedEvents.firstIndex(where: { $0.fileURL == event.fileURL }) {
            queuedEvents[existingIndex] = mergedEvent(existing: queuedEvents[existingIndex], incoming: event)
        } else {
            queuedEvents.append(event)
        }

        if let folderWatchSession {
            queuedFolderWatchSession = folderWatchSession
        }
        queuedOpenOrigin = origin

        flushRetryCount = 0
        scheduleFlush(after: .milliseconds(90), onFlushRequested: onFlushRequested)
    }

    func consumeBatchIfPossible(
        canFlushImmediately: Bool,
        onFlushRequested: @escaping @MainActor () -> Void
    ) -> FolderWatchOpenBatch? {
        guard !queuedEvents.isEmpty else {
            flushTask = nil
            return nil
        }

        guard canFlushImmediately else {
            if flushRetryCount < 10 {
                flushRetryCount += 1
                scheduleFlush(after: .milliseconds(60), onFlushRequested: onFlushRequested)
            } else {
                flushTask = nil
            }
            return nil
        }

        let queuedEvents = queuedEvents
        let batch = FolderWatchOpenBatch(
            fileURLs: queuedEvents.map(\.fileURL),
            initialDiffBaselineMarkdownByURL: queuedEvents.reduce(into: [:]) { result, event in
                guard let previousMarkdown = event.previousMarkdown else {
                    return
                }
                result[event.fileURL] = previousMarkdown
            },
            folderWatchSession: queuedFolderWatchSession,
            openOrigin: queuedOpenOrigin
        )

        self.queuedEvents = []
        queuedFolderWatchSession = nil
        queuedOpenOrigin = .manual
        flushTask = nil
        flushRetryCount = 0
        return batch
    }

    private func scheduleFlush(
        after delay: Duration,
        onFlushRequested: @escaping @MainActor () -> Void
    ) {
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            onFlushRequested()
        }
    }

    private func mergedEvent(
        existing: ReaderFolderWatchChangeEvent,
        incoming: ReaderFolderWatchChangeEvent
    ) -> ReaderFolderWatchChangeEvent {
        guard existing.kind == .added else {
            return incoming
        }

        return ReaderFolderWatchChangeEvent(
            fileURL: existing.fileURL,
            kind: .added,
            previousMarkdown: nil
        )
    }
}