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
}

private struct AutoOpenDiffBaselineRecord {
    let markdown: String
    let capturedAt: Date
}

final class ReaderFolderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning {
    private let minimumDiffBaselineAge: TimeInterval
    private let maximumHistoryDepth = 32
    private var baselineHistoryByFileURL: [URL: [AutoOpenDiffBaselineRecord]] = [:]

    init(minimumDiffBaselineAge: TimeInterval = 10) {
        self.minimumDiffBaselineAge = max(0, minimumDiffBaselineAge)
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
        let liveEvents = eventsWithAgedDiffBaselines(from: eligible, now: .now)
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
        baselineHistoryByFileURL = [:]
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
            var history = baselineHistoryByFileURL[fileURL] ?? []
            if history.last?.markdown != previousMarkdown {
                history.append(AutoOpenDiffBaselineRecord(markdown: previousMarkdown, capturedAt: now))
            }
            if history.count > maximumHistoryDepth {
                history.removeFirst(history.count - maximumHistoryDepth)
            }
            baselineHistoryByFileURL[fileURL] = history

            let agedBaseline = history.last(where: {
                now.timeIntervalSince($0.capturedAt) >= minimumDiffBaselineAge
            })?.markdown
            let fallbackBaseline = history.first?.markdown ?? previousMarkdown
            return ReaderFolderWatchChangeEvent(
                fileURL: fileURL,
                kind: .modified,
                previousMarkdown: agedBaseline ?? fallbackBaseline
            )
        }
    }
}
