import Foundation

enum AmberTerminalTheme {
    static let definition = ThemeDefinition(
        kind: .amberTerminal,
        displayName: ReaderThemeKind.amberTerminal.displayName,
        colors: ReaderTheme.theme(for: .amberTerminal),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-amber-terminal")
    }

    static var syntaxCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-amber-terminal-syntax")
    }

    static let previewPalette: SyntaxThemePreviewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#FFB000",
        blockBackgroundHex: "#1F1600",
        blockBorderHex: "#3D2E00",
        commentHex: "#806020",
        keywordHex: "#FFCC00",
        stringHex: "#CC8800",
        numberHex: "#FF9500",
        titleHex: "#FFC040",
        builtInHex: "#E0A000"
    )
}
