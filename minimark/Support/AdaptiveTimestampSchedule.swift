import SwiftUI

/// A `TimelineSchedule` that adapts its update frequency based on the age of a timestamp.
///
/// Recently-changed documents update every 5 seconds; older ones progressively less often.
/// Documents with no timestamp or deleted files never trigger updates.
struct AdaptiveTimestampSchedule: TimelineSchedule {

    let lastModified: Date?

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(lastModified: lastModified, startDate: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {

        let lastModified: Date?
        var nextDate: Date

        init(lastModified: Date?, startDate: Date) {
            self.lastModified = lastModified
            self.nextDate = startDate
        }

        mutating func next() -> Date? {
            let current = nextDate
            nextDate = current.addingTimeInterval(interval(at: current))
            return current
        }

        private func interval(at date: Date) -> TimeInterval {
            guard let lastModified else { return 86_400 }

            let age = date.timeIntervalSince(lastModified)

            switch age {
            case ..<60:          return 5        // < 1 minute → every 5s
            case ..<600:         return 30       // 1–10 minutes → every 30s
            case ..<3_600:       return 120      // 10–60 minutes → every 2 min
            case ..<86_400:      return 900      // 1–24 hours → every 15 min
            default:             return 3_600    // > 24 hours → every 1 hour
            }
        }
    }
}
