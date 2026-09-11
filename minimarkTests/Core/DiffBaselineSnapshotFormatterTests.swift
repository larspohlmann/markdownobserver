import Foundation
import Testing
@testable import minimark

@Suite
struct DiffBaselineSnapshotFormatterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US_POSIX")
    // 2026-09-11 14:32:05 UTC
    private let now = Date(timeIntervalSince1970: 1_789_137_125)

    @Test func sameDayShowsTimeOnly() {
        let text = DiffBaselineSnapshotFormatter.timeText(
            for: now.addingTimeInterval(-120), relativeTo: now, calendar: calendar, locale: locale
        )
        #expect(text == "14:30:05")
    }

    @Test func yesterdayIsPrefixed() {
        let text = DiffBaselineSnapshotFormatter.timeText(
            for: now.addingTimeInterval(-86_400), relativeTo: now, calendar: calendar, locale: locale
        )
        #expect(text == "Yesterday 14:32:05")
    }

    @Test func olderShowsDayAndMonth() {
        let text = DiffBaselineSnapshotFormatter.timeText(
            for: now.addingTimeInterval(-3 * 86_400), relativeTo: now, calendar: calendar, locale: locale
        )
        #expect(text == "Sep 8 14:32:05")
    }

    @Test func menuTitleCombinesTimeAndRelativeAge() {
        let snapshot = DiffBaselineSnapshot(markdown: "", capturedAt: now.addingTimeInterval(-120))
        let title = DiffBaselineSnapshotFormatter.menuTitle(for: snapshot, relativeTo: now, calendar: calendar, locale: locale)
        #expect(title.hasPrefix("14:30:05 \u{00B7} "))
        #expect(title.contains("min"))
    }

    @Test func statusLabelVariants() {
        let snapshot = DiffBaselineSnapshot(markdown: "", capturedAt: now.addingTimeInterval(-120))
        let comparing = DiffBaselineSnapshotFormatter.statusLabel(
            activeBaseline: snapshot, hasSnapshots: true, relativeTo: now, calendar: calendar, locale: locale
        )
        #expect(comparing.hasPrefix("Comparing to 14:30:05 \u{00B7} "))
        #expect(DiffBaselineSnapshotFormatter.statusLabel(
            activeBaseline: nil, hasSnapshots: false, relativeTo: now, calendar: calendar, locale: locale
        ) == "No earlier snapshot")
        #expect(DiffBaselineSnapshotFormatter.statusLabel(
            activeBaseline: nil, hasSnapshots: true, relativeTo: now, calendar: calendar, locale: locale
        ) == "Not comparing")
    }
}
