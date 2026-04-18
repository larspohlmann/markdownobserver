import Foundation

enum NewspaperTheme {
    static let definition = ThemeDefinition(
        kind: .newspaper,
        displayName: ThemeKind.newspaper.displayName,
        colors: Theme.theme(for: .newspaper),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-newspaper")
    }
}
