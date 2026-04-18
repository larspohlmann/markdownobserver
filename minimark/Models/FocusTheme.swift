import Foundation

enum FocusTheme {
    static let definition = ThemeDefinition(
        kind: .focus,
        displayName: ThemeKind.focus.displayName,
        colors: Theme.theme(for: .focus),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-focus")
    }
}
