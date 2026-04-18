import Foundation

enum TufteTheme {
    static let definition = ThemeDefinition(
        kind: .tufte,
        displayName: ThemeKind.tufte.displayName,
        colors: Theme.theme(for: .tufte),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-tufte")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-tufte-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#111111",
        blockBackgroundHex: "#F5F3E9",
        blockBorderHex: "#D4CEC0",
        commentHex: "#888888",
        keywordHex: "#A01010",
        stringHex: "#444444",
        numberHex: "#553F1F",
        titleHex: "#111111",
        builtInHex: "#111111"
    )
}
