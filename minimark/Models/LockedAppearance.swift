import Foundation

nonisolated struct LockedAppearance: Equatable, Hashable, Codable, Sendable {
    let readerTheme: ThemeKind
    let baseFontSize: Double
    let syntaxTheme: SyntaxThemeKind
    let readerThemeOverride: ThemeOverride?

    init(
        readerTheme: ThemeKind,
        baseFontSize: Double,
        syntaxTheme: SyntaxThemeKind,
        readerThemeOverride: ThemeOverride? = nil
    ) {
        self.readerTheme = readerTheme
        self.baseFontSize = baseFontSize
        self.syntaxTheme = syntaxTheme
        self.readerThemeOverride = readerThemeOverride
    }

    enum CodingKeys: String, CodingKey {
        case readerTheme
        case baseFontSize
        case syntaxTheme
        case readerThemeOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readerTheme = try container.decode(ThemeKind.self, forKey: .readerTheme)
        baseFontSize = try container.decode(Double.self, forKey: .baseFontSize)
        syntaxTheme = try container.decode(SyntaxThemeKind.self, forKey: .syntaxTheme)
        readerThemeOverride = try container.decodeIfPresent(ThemeOverride.self, forKey: .readerThemeOverride)
    }
}
