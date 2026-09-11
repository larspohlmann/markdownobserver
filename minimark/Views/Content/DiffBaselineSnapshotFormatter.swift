import Foundation

/// Pure text formatting for the diff baseline status bar and its menu.
enum DiffBaselineSnapshotFormatter {
    static let noEarlierSnapshotLabel = "No earlier snapshot"
    static let notComparingLabel = "Not comparing"

    /// A fixed `HH:mm:ss` pattern, independent of the locale's 12h/24h preference,
    /// so the status bar clock always reads as a 24-hour time.
    private static func clockText(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func timeText(
        for date: Date,
        relativeTo now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let clock = clockText(for: date, calendar: calendar, locale: locale)
        if calendar.isDate(date, inSameDayAs: now) {
            return clock
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(clock)"
        }
        let day = date.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.abbreviated)
        )
        return "\(day) \(clock)"
    }

    static let justNowLabel = "just now"

    /// A baseline snapshot is always a prior version, so a freshly recorded one
    /// reads as "just now" instead of a rounding artifact like "in 0 sec" or
    /// "0 sec ago". Below the threshold, or when clock skew puts `capturedAt`
    /// ahead of `now`, use "just now"; otherwise the standard relative age.
    private static let justNowThreshold: TimeInterval = 5

    static func relativeAgeText(for date: Date, relativeTo now: Date) -> String {
        if now.timeIntervalSince(date) < justNowThreshold {
            return justNowLabel
        }
        return StatusFormatting.relativeText(for: date, relativeTo: now)
    }

    static func menuTitle(
        for snapshot: DiffBaselineSnapshot,
        relativeTo now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let time = timeText(for: snapshot.capturedAt, relativeTo: now, calendar: calendar, locale: locale)
        let relative = relativeAgeText(for: snapshot.capturedAt, relativeTo: now)
        return "\(time) \u{00B7} \(relative)"
    }

    static func statusLabel(
        activeBaseline: DiffBaselineSnapshot?,
        hasSnapshots: Bool,
        relativeTo now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        guard let activeBaseline else {
            return hasSnapshots ? notComparingLabel : noEarlierSnapshotLabel
        }
        return "Comparing to \(menuTitle(for: activeBaseline, relativeTo: now, calendar: calendar, locale: locale))"
    }

    /// Compact form for the UI-test accessibility summary: `none`, `auto:HH:mm:ss`, `pinned:HH:mm:ss`.
    static func accessibilityBaseline(
        mode: DiffBaselineSelectionMode,
        activeBaseline: DiffBaselineSnapshot?,
        calendar: Calendar = .current
    ) -> String {
        guard let activeBaseline else { return "none" }
        let clock = clockText(
            for: activeBaseline.capturedAt, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")
        )
        switch mode {
        case .automatic: return "auto:\(clock)"
        case .pinned: return "pinned:\(clock)"
        }
    }
}
