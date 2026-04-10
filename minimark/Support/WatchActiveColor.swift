import SwiftUI

enum WatchActiveColor {
    static func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.59, green: 0.49, blue: 1.0)
            : Color(red: 0.34, green: 0.24, blue: 0.71)
    }
}
