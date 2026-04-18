import Foundation

enum NordTheme {
    static let definition = ThemeDefinition(
        kind: .nord,
        displayName: ThemeKind.nord.displayName,
        colors: Theme.theme(for: .nord),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-nord")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-nord-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#ECEFF4",
        blockBackgroundHex: "#242933",
        blockBorderHex: "#3B4252",
        commentHex: "#4C566A",
        keywordHex: "#81A1C1",
        stringHex: "#A3BE8C",
        numberHex: "#B48EAD",
        titleHex: "#8FBCBB",
        builtInHex: "#88C0D0"
    )
}
