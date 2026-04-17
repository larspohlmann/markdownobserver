import Foundation

enum GreenTerminalTheme {
    static let definition = ThemeDefinition(
        kind: .greenTerminal,
        displayName: ThemeKind.greenTerminal.displayName,
        colors: Theme.theme(for: .greenTerminal),
        customCSS: customCSS,
        customJavaScript: digitalRainJavaScript,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let staticDefinition = ThemeDefinition(
        kind: .greenTerminalStatic,
        displayName: ThemeKind.greenTerminalStatic.displayName,
        colors: Theme.theme(for: .greenTerminalStatic),
        customCSS: customCSS,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static var customCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-green-terminal")
    }

    static var syntaxCSS: String {
        BundledAssetLoader.loadBundledCSS(named: "theme-green-terminal-syntax")
    }

    static let previewPalette: SyntaxThemePreviewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#00FF41",
        blockBackgroundHex: "#0A0A0A",
        blockBorderHex: "#003B00",
        commentHex: "#2E7D32",
        keywordHex: "#00FF41",
        stringHex: "#41FF7F",
        numberHex: "#76FF03",
        titleHex: "#69F0AE",
        builtInHex: "#00E676"
    )

    // MARK: - Digital Rain Animation

    static var digitalRainJavaScript: String {
        BundledAssetLoader.loadBundledJS(named: "theme-green-terminal-rain")
    }
}
