import Foundation

nonisolated struct LockedAppearance: Equatable, Hashable, Codable, Sendable {
    let readerTheme: ReaderThemeKind
    let baseFontSize: Double
    let syntaxTheme: SyntaxThemeKind
}
