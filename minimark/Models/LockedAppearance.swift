import Foundation

nonisolated struct LockedAppearance: Equatable, Hashable, Codable, Sendable {
    let readerTheme: ThemeKind
    let baseFontSize: Double
    let syntaxTheme: SyntaxThemeKind
}
