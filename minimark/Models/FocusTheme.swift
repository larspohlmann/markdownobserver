import Foundation

enum FocusTheme {
    static let definition = ThemeDefinition(
        kind: .focus,
        displayName: ReaderThemeKind.focus.displayName,
        colors: ReaderTheme.theme(for: .focus),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )

    static var customCSS: String {
        ReaderBundledAssetLoader.loadBundledCSS(named: "theme-focus")
    }
}
