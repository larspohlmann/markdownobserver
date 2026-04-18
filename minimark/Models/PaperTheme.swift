import Foundation

enum PaperTheme {
    static let definition = ThemeDefinition(
        kind: .paper,
        displayName: ThemeKind.paper.displayName,
        colors: Theme.theme(for: .paper),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-paper")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-paper-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#1A1A1A",
        blockBackgroundHex: "#F4F4F0",
        blockBorderHex: "#E4E2DC",
        commentHex: "#888888",
        keywordHex: "#0B5FB8",
        stringHex: "#116622",
        numberHex: "#8A3FAE",
        titleHex: "#0B0B0B",
        builtInHex: "#AA3A8F"
    )
}
