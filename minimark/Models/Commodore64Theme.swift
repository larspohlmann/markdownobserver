import Foundation

enum Commodore64Theme {
    static let definition = ThemeDefinition(
        kind: .commodore64,
        displayName: ThemeKind.commodore64.displayName,
        colors: Theme.theme(for: .commodore64),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-commodore64")
    }

    static var syntaxCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-commodore64-syntax")
    }

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#A0A0FF",
        blockBackgroundHex: "#352879",
        blockBorderHex: "#504694",
        commentHex: "#504694",
        keywordHex: "#FFFFFF",
        stringHex: "#5CAB5E",
        numberHex: "#C9D487",
        titleHex: "#6ABFC6",
        builtInHex: "#887ECB"
    )
}
