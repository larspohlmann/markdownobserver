import Foundation

struct FolderWatchAutoOpenPlan: Equatable, Sendable {
    let autoOpenEvents: [FolderWatchChangeEvent]
    let warning: FolderWatchAutoOpenWarning?
}

protocol FolderWatchAutoOpenPlanning: AnyObject {
    func initialPlan(
        for events: [FolderWatchChangeEvent],
        activeSession: FolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> FolderWatchAutoOpenPlan

    func livePlan(
        for events: [FolderWatchChangeEvent],
        activeSession: FolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> FolderWatchAutoOpenPlan

    func resetTransientState()
    func updateMinimumDiffBaselineAge(_ age: TimeInterval)
}

final class FolderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanning {
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
        for events: [FolderWatchChangeEvent],
        activeSession: FolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> FolderWatchAutoOpenPlan {
        let eligibleEvents = eligibleEvents(
            from: events,
            currentDocumentFileURL: currentDocumentFileURL
        )
        let autoOpenEvents = Array(
            eligibleEvents.prefix(FolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
        )

        let warning: FolderWatchAutoOpenWarning?
        if let activeSession {
            let omittedFileURLs = Array(eligibleEvents.dropFirst(autoOpenEvents.count)).map(\.fileURL)
            if omittedFileURLs.isEmpty {
                warning = nil
            } else {
                warning = FolderWatchAutoOpenWarning(
                    folderURL: activeSession.folderURL,
                    autoOpenedFileCount: autoOpenEvents.count,
                    omittedFileURLs: omittedFileURLs
                )
            }
        } else {
            warning = nil
        }

        return FolderWatchAutoOpenPlan(
            autoOpenEvents: autoOpenEvents,
            warning: warning
        )
    }

    func liveOpenEvents(
        for events: [FolderWatchChangeEvent],
        currentDocumentFileURL: URL?
    ) -> [FolderWatchChangeEvent] {
        livePlan(
            for: events,
            activeSession: nil,
            currentDocumentFileURL: currentDocumentFileURL
        ).autoOpenEvents
    }

    func livePlan(
        for events: [FolderWatchChangeEvent],
        activeSession: FolderWatchSession?,
        currentDocumentFileURL: URL?
    ) -> FolderWatchAutoOpenPlan {
        let eligible = eligibleEvents(from: events, currentDocumentFileURL: currentDocumentFileURL)
        let liveEvents = eventsWithAgedDiffBaselines(from: eligible, now: nowProvider())
        let autoOpenEvents = Array(
            liveEvents.prefix(FolderWatchAutoOpenPolicy.maximumLiveAutoOpenFileCount)
        )

        let warning: FolderWatchAutoOpenWarning?
        if let activeSession {
            let omittedFileURLs = Array(liveEvents.dropFirst(autoOpenEvents.count)).map(\.fileURL)
            if omittedFileURLs.isEmpty {
                warning = nil
            } else {
                warning = FolderWatchAutoOpenWarning(
                    folderURL: activeSession.folderURL,
                    autoOpenedFileCount: autoOpenEvents.count,
                    omittedFileURLs: omittedFileURLs
                )
            }
        } else {
            warning = nil
        }

        return FolderWatchAutoOpenPlan(
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
        from events: [FolderWatchChangeEvent],
        currentDocumentFileURL: URL?
    ) -> [FolderWatchChangeEvent] {
        events
            .map {
                FolderWatchChangeEvent(
                    fileURL: FileRouting.normalizedFileURL($0.fileURL),
                    kind: $0.kind,
                    previousMarkdown: $0.previousMarkdown
                )
            }
            .filter { FileRouting.isSupportedMarkdownFileURL($0.fileURL) }
            .filter { event in
                guard let currentDocumentFileURL else {
                    return true
                }

                return event.fileURL != currentDocumentFileURL
            }
    }

    private func eventsWithAgedDiffBaselines(
        from events: [FolderWatchChangeEvent],
        now: Date
    ) -> [FolderWatchChangeEvent] {
        events.map { event in
            guard event.kind == .modified, let previousMarkdown = event.previousMarkdown else {
                return event
            }

            let fileURL = FileRouting.normalizedFileURL(event.fileURL)
            let baseline = diffBaselineTracker.recordAndSelectBaseline(
                markdown: previousMarkdown,
                for: fileURL,
                at: now
            )
            return FolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: baseline
            )
        }
    }
}
