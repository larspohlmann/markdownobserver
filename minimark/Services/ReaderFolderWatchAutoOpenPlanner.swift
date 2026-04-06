import Foundation

struct ReaderFolderWatchAutoOpenPlan: Equatable, Sendable {
    let autoOpenEvents: [ReaderFolderWatchChangeEvent]
    let warning: ReaderFolderWatchAutoOpenWarning?
}

protocol ReaderFolderWatchAutoOpenPlanning: AnyObject {
    func initialPlan(
        for events: [ReaderFolderWatchChangeEvent],
        activeSession: ReaderFolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> ReaderFolderWatchAutoOpenPlan

    func livePlan(
        for events: [ReaderFolderWatchChangeEvent],
        activeSession: ReaderFolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> ReaderFolderWatchAutoOpenPlan

    func resetTransientState()
    func updateMinimumDiffBaselineAge(_ age: TimeInterval)
}

final class ReaderFolderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning {
    private let diffBaselineTracker: DiffBaselineTracking
    private let nowProvider: () -> Date

    init(
        minimumDiffBaselineAge: TimeInterval = 10,
        nowProvider: @escaping () -> Date = { .now }
    ) {
        self.diffBaselineTracker = DiffBaselineTracker(minimumAge: minimumDiffBaselineAge)
        self.nowProvider = nowProvider
    }

    func initialPlan(
        for events: [ReaderFolderWatchChangeEvent],
        activeSession: ReaderFolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> ReaderFolderWatchAutoOpenPlan {
        let eligibleEvents = eligibleEvents(
            from: events,
            currentDocumentFileURL: currentDocumentFileURL
        )
        let autoOpenEvents = Array(
            eligibleEvents.prefix(ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
        )

        let warning: ReaderFolderWatchAutoOpenWarning?
        if let activeSession {
            let omittedFileURLs = Array(eligibleEvents.dropFirst(autoOpenEvents.count)).map(\.fileURL)
            if omittedFileURLs.isEmpty {
                warning = nil
            } else {
                warning = ReaderFolderWatchAutoOpenWarning(
                    folderURL: activeSession.folderURL,
                    autoOpenedFileCount: autoOpenEvents.count,
                    omittedFileURLs: omittedFileURLs
                )
            }
        } else {
            warning = nil
        }

        return ReaderFolderWatchAutoOpenPlan(
            autoOpenEvents: autoOpenEvents,
            warning: warning
        )
    }

    func liveOpenEvents(
        for events: [ReaderFolderWatchChangeEvent],
        currentDocumentFileURL: URL?
    ) -> [ReaderFolderWatchChangeEvent] {
        livePlan(
            for: events,
            activeSession: nil,
            currentDocumentFileURL: currentDocumentFileURL
        ).autoOpenEvents
    }

    func livePlan(
        for events: [ReaderFolderWatchChangeEvent],
        activeSession: ReaderFolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> ReaderFolderWatchAutoOpenPlan {
        let eligible = eligibleEvents(from: events, currentDocumentFileURL: currentDocumentFileURL)
        let liveEvents = eventsWithAgedDiffBaselines(from: eligible, now: nowProvider())
        let autoOpenEvents = Array(
            liveEvents.prefix(ReaderFolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)
        )

        let warning: ReaderFolderWatchAutoOpenWarning?
        if let activeSession {
            let omittedFileURLs = Array(liveEvents.dropFirst(autoOpenEvents.count)).map(\.fileURL)
            if omittedFileURLs.isEmpty {
                warning = nil
            } else {
                warning = ReaderFolderWatchAutoOpenWarning(
                    folderURL: activeSession.folderURL,
                    autoOpenedFileCount: autoOpenEvents.count,
                    omittedFileURLs: omittedFileURLs
                )
            }
        } else {
            warning = nil
        }

        return ReaderFolderWatchAutoOpenPlan(
            autoOpenEvents: autoOpenEvents,
            warning: warning
        )
    }

    func resetTransientState() {
        diffBaselineTracker.reset()
    }

    func updateMinimumDiffBaselineAge(_ age: TimeInterval) {
        diffBaselineTracker.updateMinimumAge(age)
    }

    private func eligibleEvents(
        from events: [ReaderFolderWatchChangeEvent],
        currentDocumentFileURL: URL?
    ) -> [ReaderFolderWatchChangeEvent] {
        events
            .map {
                ReaderFolderWatchChangeEvent(
                    fileURL: ReaderFileRouting.normalizedFileURL($0.fileURL),
                    kind: $0.kind,
                    previousMarkdown: $0.previousMarkdown
                )
            }
            .filter { ReaderFileRouting.isSupportedMarkdownFileURL($0.fileURL) }
            .filter { event in
                guard let currentDocumentFileURL else {
                    return true
                }

                return event.fileURL != currentDocumentFileURL
            }
    }

    private func eventsWithAgedDiffBaselines(
        from events: [ReaderFolderWatchChangeEvent],
        now: Date
    ) -> [ReaderFolderWatchChangeEvent] {
        events.map { event in
            guard event.kind == .modified, let previousMarkdown = event.previousMarkdown else {
                return event
            }

            let fileURL = ReaderFileRouting.normalizedFileURL(event.fileURL)
            let baseline = diffBaselineTracker.recordAndSelectBaseline(
                markdown: previousMarkdown,
                for: fileURL,
                at: now
            )
            return ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: baseline
            )
        }
    }
}
