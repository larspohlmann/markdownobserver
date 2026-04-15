import Foundation

enum NewspaperTheme {
    static let definition = ThemeDefinition(
        kind: .newspaper,
        displayName: ReaderThemeKind.newspaper.displayName,
        colors: ReaderTheme.theme(for: .newspaper),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static var customCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-newspaper")
    }
}
