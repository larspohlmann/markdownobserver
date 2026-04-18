import Foundation

enum NeonTheme {
    static let definition = ThemeDefinition(
        kind: .neon,
        displayName: ThemeKind.neon.displayName,
        colors: Theme.theme(for: .neon),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-neon")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-neon-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#F2E8FF",
        blockBackgroundHex: "#140F2E",
        blockBorderHex: "#3A1E6E",
        commentHex: "#6A4A9A",
        keywordHex: "#FF2E8A",
        stringHex: "#00E8D6",
        numberHex: "#B478E8",
        titleHex: "#FFCA28",
        builtInHex: "#FF2E8A"
    )
}
