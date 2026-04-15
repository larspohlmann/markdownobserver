import Foundation

enum GameBoyTheme {
    static let definition = ThemeDefinition(
        kind: .gameBoy,
        displayName: ReaderThemeKind.gameBoy.displayName,
        colors: ReaderTheme.theme(for: .gameBoy),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-gameboy")
    }

    static var syntaxCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-gameboy-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#0F380F",
        blockBackgroundHex: "#8BAC0F",
        blockBorderHex: "#306230",
        commentHex: "#306230",
        keywordHex: "#0F380F",
        stringHex: "#306230",
        numberHex: "#0F380F",
        titleHex: "#0F380F",
        builtInHex: "#306230"
    )
}
