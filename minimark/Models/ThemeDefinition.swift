import Foundation

struct ThemeDefinition: Equatable, Sendable {
    let kind: ThemeKind
    let displayName: String
    let colors: Theme
    let customCSS: String?
    let customJavaScript: String?
    let providesSyntaxHighlighting: Bool
    let syntaxCSS: String?
    let syntaxPreviewPalette: SyntaxThemePreviewPalette?
}

extension ThemeKind {
    var themeDefinition: ThemeDefinition {
        switch self {
        case .blackOnWhite, .whiteOnBlack, .darkGreyOnLightGrey, .lightGreyOnDarkGrey, .gruvboxDark, .gruvboxLight, .dracula, .monokai:
            return ThemeDefinition(
                kind: self,
                displayName: displayName,
                colors: Theme.theme(for: self),
                customCSS: nil,
                customJavaScript: nil,
                providesSyntaxHighlighting: false,
                syntaxCSS: nil,
                syntaxPreviewPalette: nil
            )
        case .amberTerminal:
            return AmberTerminalTheme.definition
        case .greenTerminal:
            return GreenTerminalTheme.definition
        case .greenTerminalStatic:
            return GreenTerminalTheme.staticDefinition
        case .newspaper:
            return NewspaperTheme.definition
        case .focus:
            return FocusTheme.definition
        case .commodore64:
            return Commodore64Theme.definition
        case .gameBoy:
            return GameBoyTheme.definition
        case .reef:
            return ReefTheme.definition
        case .neon:
            return NeonTheme.definition
        case .nord:
            return NordTheme.definition
        case .tokyoNight:
            return TokyoNightTheme.definition
        case .tufte:
            return TufteTheme.definition
        case .paper:
            return PaperTheme.definition
        }
    }
}
