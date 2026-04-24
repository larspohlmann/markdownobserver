import Foundation

nonisolated struct ThemeOverride: Equatable, Hashable, Codable, Sendable {
    var themeKind: ThemeKind
    var backgroundHex: String?
    var foregroundHex: String?

    var isEmpty: Bool {
        backgroundHex == nil && foregroundHex == nil
    }
}
