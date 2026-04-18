import Foundation

enum ReefTheme {
    static let definition = ThemeDefinition(
        kind: .reef,
        displayName: ThemeKind.reef.displayName,
        colors: Theme.theme(for: .reef),
        customCSS: customCSS,
        customJavaScript: causticsJavaScript,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-reef")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-reef-syntax")
    }

    static var causticsJavaScript: String {
        BundledAssetLoader.loadBundledJS(named: "theme-reef-caustics")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#D0F0E8",
        blockBackgroundHex: "#041A1C",
        blockBorderHex: "#144048",
        commentHex: "#488078",
        keywordHex: "#E8C070",
        stringHex: "#4ADCBA",
        numberHex: "#A8E8D0",
        titleHex: "#E8A0C8",
        builtInHex: "#74D2C8"
    )
}
