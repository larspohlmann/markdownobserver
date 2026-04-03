import Foundation

protocol DiffBaselineTracking: AnyObject {
    func recordAndSelectBaseline(
        markdown: String,
        for fileURL: URL,
        at now: Date
    ) -> String

    func updateMinimumAge(_ age: TimeInterval)
    func reset()
}

final class DiffBaselineTracker: DiffBaselineTracking {
    private var minimumAge: TimeInterval
    private let maximumHistoryDepth: Int
    private var historyByFileURL: [URL: [Record]] = [:]

    init(minimumAge: TimeInterval, maximumHistoryDepth: Int = 32) {
        self.minimumAge = max(0, minimumAge)
        self.maximumHistoryDepth = maximumHistoryDepth
    }

    func recordAndSelectBaseline(
        markdown: String,
        for fileURL: URL,
        at now: Date
    ) -> String {
        var history = historyByFileURL[fileURL] ?? []

        if history.last?.markdown != markdown {
            history.append(Record(markdown: markdown, capturedAt: now))
        }
        if history.count > maximumHistoryDepth {
            history.removeFirst(history.count - maximumHistoryDepth)
        }
        historyByFileURL[fileURL] = history

        // Exclude the just-recorded entry so the baseline is always from a prior
        // call.  With any production minimumAge (≥ 10 s) the just-recorded entry
        // (age 0) would never qualify anyway; dropLast() makes that invariant
        // explicit and prevents surprising results when minimumAge is 0 in tests.
        let agedBaseline = history.dropLast().last(where: {
            now.timeIntervalSince($0.capturedAt) >= minimumAge
        })?.markdown
        return agedBaseline ?? history.first?.markdown ?? markdown
    }

    func updateMinimumAge(_ age: TimeInterval) {
        minimumAge = max(0, age)
    }

    func reset() {
        historyByFileURL = [:]
    }
}

private extension DiffBaselineTracker {
    struct Record {
        let markdown: String
        let capturedAt: Date
    }
}
