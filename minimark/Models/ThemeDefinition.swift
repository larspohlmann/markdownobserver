import Foundation

struct ThemeDefinition: Equatable, Sendable {
    let kind: ReaderThemeKind
    let displayName: String
    let colors: ReaderTheme
    let customCSS: String?
    let customJavaScript: String?
    let providesSyntaxHighlighting: Bool
    let syntaxCSS: String?
    let syntaxPreviewPalette: SyntaxThemePreviewPalette?
}

extension ReaderThemeKind {
    var themeDefinition: ThemeDefinition {
        switch self {
        case .blackOnWhite, .whiteOnBlack, .darkGreyOnLightGrey, .lightGreyOnDarkGrey:
            return ThemeDefinition(
                kind: self,
                displayName: displayName,
                colors: ReaderTheme.theme(for: self),
                customCSS: nil,
                customJavaScript: nil,
                providesSyntaxHighlighting: false,
                syntaxCSS: nil,
                syntaxPreviewPalette: nil
            )
        case .amberTerminal:
            return AmberTerminalTheme.definition
        }
    }
}
