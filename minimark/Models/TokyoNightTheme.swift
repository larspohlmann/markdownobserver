import Foundation

enum TokyoNightTheme {
    static let definition = ThemeDefinition(
        kind: .tokyoNight,
        displayName: ThemeKind.tokyoNight.displayName,
        colors: Theme.theme(for: .tokyoNight),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-tokyonight")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-tokyonight-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#C0CAF5",
        blockBackgroundHex: "#16161E",
        blockBorderHex: "#292E42",
        commentHex: "#565F89",
        keywordHex: "#BB9AF7",
        stringHex: "#9ECE6A",
        numberHex: "#FF9E64",
        titleHex: "#7AA2F7",
        builtInHex: "#7DCFFF"
    )
}
