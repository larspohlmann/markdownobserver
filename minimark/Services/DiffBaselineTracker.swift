import Foundation

protocol DiffBaselineTracking: AnyObject {
    var currentMinimumAge: TimeInterval { get }

    /// Appends `markdown` unless it equals the newest record for `fileURL`.
    /// Returns the newest record after the call.
    @discardableResult
    func record(markdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot

    /// `record` followed by the lookback selection: the newest record older than
    /// `currentMinimumAge`, excluding the just-recorded one; else the oldest
    /// record; else the just-recorded one.
    func recordAndSelectBaseline(markdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot

    /// Newest first.
    func snapshots(for fileURL: URL) -> [DiffBaselineSnapshot]
    func snapshot(id: DiffBaselineSnapshot.ID, for fileURL: URL) -> DiffBaselineSnapshot?

    func updateMinimumAge(_ age: TimeInterval)
    func reset()
}

final class DiffBaselineTracker: DiffBaselineTracking {
    private(set) var currentMinimumAge: TimeInterval
    private let maximumHistoryDepth: Int
    /// Oldest first.
    private var historyByFileURL: [URL: [DiffBaselineSnapshot]] = [:]

    init(minimumAge: TimeInterval, maximumHistoryDepth: Int = 32) {
        self.currentMinimumAge = max(0, minimumAge)
        self.maximumHistoryDepth = maximumHistoryDepth
    }

    /// The lookback rule shared by the tracker and `DiffBaselineSelectionController`.
    /// `history` is oldest first. `excluding` removes one id (the just-recorded
    /// entry) from the aged candidates but not from the oldest-record fallback.
    static func agedSelection(
        fromOldestFirst history: [DiffBaselineSnapshot],
        minimumAge: TimeInterval,
        now: Date,
        excluding excludedID: DiffBaselineSnapshot.ID?
    ) -> DiffBaselineSnapshot? {
        let aged = history.last(where: { candidate in
            candidate.id != excludedID
                && now.timeIntervalSince(candidate.capturedAt) >= minimumAge
        })
        return aged ?? history.first
    }

    @discardableResult
    func record(markdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot {
        var history = historyByFileURL[fileURL] ?? []

        if history.last?.markdown != markdown {
            history.append(DiffBaselineSnapshot(markdown: markdown, capturedAt: now))
        }
        if history.count > maximumHistoryDepth {
            history.removeFirst(history.count - maximumHistoryDepth)
        }
        historyByFileURL[fileURL] = history
        return history[history.count - 1]
    }

    func recordAndSelectBaseline(markdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot {
        let newest = record(markdown: markdown, for: fileURL, at: now)
        let history = historyByFileURL[fileURL] ?? []
        return Self.agedSelection(
            fromOldestFirst: history,
            minimumAge: currentMinimumAge,
            now: now,
            excluding: newest.id
        ) ?? newest
    }

    func snapshots(for fileURL: URL) -> [DiffBaselineSnapshot] {
        (historyByFileURL[fileURL] ?? []).reversed()
    }

    func snapshot(id: DiffBaselineSnapshot.ID, for fileURL: URL) -> DiffBaselineSnapshot? {
        historyByFileURL[fileURL]?.first(where: { $0.id == id })
    }

    func updateMinimumAge(_ age: TimeInterval) {
        currentMinimumAge = max(0, age)
    }

    func reset() {
        historyByFileURL = [:]
    }
}
