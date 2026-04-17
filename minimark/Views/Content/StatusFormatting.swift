import Foundation

enum StatusFormatting {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeText(for date: Date, relativeTo referenceDate: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }
}