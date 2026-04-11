import Foundation
import SwiftUI
import Testing
@testable import minimark

@Suite
struct AdaptiveTimestampScheduleTests {

    private func intervals(
        lastModified: Date?,
        startDate: Date,
        count: Int
    ) -> [TimeInterval] {
        let schedule = AdaptiveTimestampSchedule(lastModified: lastModified)
        var entries = schedule.entries(from: startDate, mode: .normal)
        var dates: [Date] = []
        for _ in 0..<count {
            guard let date = entries.next() else { break }
            dates.append(date)
        }
        return zip(dates, dates.dropFirst()).map { $1.timeIntervalSince($0) }
    }

    // MARK: - Tier boundaries

    @Test func recentDocumentUpdatesEvery5Seconds() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-10) // 10s ago
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 4)

        for gap in gaps {
            #expect(gap == 5)
        }
    }

    @Test func oneToTenMinutesUpdatesEvery30Seconds() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-120) // 2 min ago
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 4)

        for gap in gaps {
            #expect(gap == 30)
        }
    }

    @Test func tenToSixtyMinutesUpdatesEvery2Minutes() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-1800) // 30 min ago
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 4)

        for gap in gaps {
            #expect(gap == 120)
        }
    }

    @Test func oneToTwentyFourHoursUpdatesEvery15Minutes() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-7200) // 2 hours ago
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 4)

        for gap in gaps {
            #expect(gap == 900)
        }
    }

    @Test func olderThan24HoursUpdatesEveryHour() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-172_800) // 2 days ago
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 4)

        for gap in gaps {
            #expect(gap == 3600)
        }
    }

    // MARK: - Tier transitions

    @Test func transitionsFromFastToSlowerTier() {
        let now = Date()
        let lastModified = now.addingTimeInterval(-55) // 55s ago, just under 1 min
        let schedule = AdaptiveTimestampSchedule(lastModified: lastModified)
        var entries = schedule.entries(from: now, mode: .normal)

        let first = entries.next()!
        let second = entries.next()!
        let firstGap = second.timeIntervalSince(first)
        #expect(firstGap == 5) // still in <1min tier

        // After the 5s tick, age is 60s → transitions to 30s tier
        let third = entries.next()!
        let secondGap = third.timeIntervalSince(second)
        #expect(secondGap == 30)
    }

    // MARK: - Edge cases

    @Test func nilLastModifiedUsesLargeInterval() {
        let now = Date()
        let gaps = intervals(lastModified: nil, startDate: now, count: 3)

        for gap in gaps {
            #expect(gap == 86_400)
        }
    }

    @Test func futureLastModifiedTreatedAsRecent() {
        let now = Date()
        let lastModified = now.addingTimeInterval(10) // 10s in the future
        let gaps = intervals(lastModified: lastModified, startDate: now, count: 3)

        // Negative age falls into ..<60 tier
        for gap in gaps {
            #expect(gap == 5)
        }
    }

    @Test func firstEntryIsStartDate() {
        let now = Date()
        let schedule = AdaptiveTimestampSchedule(lastModified: now)
        var entries = schedule.entries(from: now, mode: .normal)

        let first = entries.next()!
        #expect(first == now)
    }
}
