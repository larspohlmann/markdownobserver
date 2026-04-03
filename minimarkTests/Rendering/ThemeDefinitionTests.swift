import XCTest
@testable import minimark

final class ThemeDefinitionTests: XCTestCase {

    func testSimpleThemeDefinitionHasNilCustomCSS() {
        let definition = ReaderThemeKind.blackOnWhite.themeDefinition
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertNil(definition.syntaxPreviewPalette)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
    }

    func testSimpleThemeDefinitionHasCorrectColors() {
        let definition = ReaderThemeKind.blackOnWhite.themeDefinition
        let expectedColors = ReaderTheme.theme(for: .blackOnWhite)
        XCTAssertEqual(definition.colors, expectedColors)
        XCTAssertEqual(definition.kind, .blackOnWhite)
        XCTAssertEqual(definition.displayName, ReaderThemeKind.blackOnWhite.displayName)
    }

    func testAllExistingThemesProduceValidDefinitions() {
        let simpleKinds: [ReaderThemeKind] = [
            .blackOnWhite, .whiteOnBlack, .darkGreyOnLightGrey, .lightGreyOnDarkGrey
        ]
        for kind in simpleKinds {
            let definition = kind.themeDefinition
            XCTAssertEqual(definition.kind, kind, "Kind mismatch for \(kind)")
            XCTAssertEqual(definition.displayName, kind.displayName, "Display name mismatch for \(kind)")
            XCTAssertEqual(definition.colors, ReaderTheme.theme(for: kind), "Colors mismatch for \(kind)")
            XCTAssertNil(definition.customCSS, "Simple theme \(kind) should not have custom CSS")
            XCTAssertNil(definition.customJavaScript, "Simple theme \(kind) should not have custom JS")
            XCTAssertNil(definition.syntaxCSS, "Simple theme \(kind) should not have syntax CSS")
            XCTAssertNil(definition.syntaxPreviewPalette, "Simple theme \(kind) should not have syntax preview palette")
            XCTAssertFalse(definition.providesSyntaxHighlighting, "Simple theme \(kind) should not provide syntax highlighting")
        }
    }

    // MARK: - Amber Terminal Theme

    func testAmberTerminalHasCorrectDisplayName() {
        let kind = ReaderThemeKind.amberTerminal
        XCTAssertEqual(kind.displayName, "Amber Terminal")
        XCTAssertTrue(kind.isDark)
    }

    func testAmberTerminalDefinitionProvidesCustomCSS() {
        let definition = ReaderThemeKind.amberTerminal.themeDefinition
        XCTAssertNotNil(definition.customCSS)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
        XCTAssertNil(definition.customJavaScript)
    }

    func testAmberTerminalColorsAreAmberPalette() {
        let definition = ReaderThemeKind.amberTerminal.themeDefinition
        XCTAssertFalse(definition.colors.hasLightBackground)
        XCTAssertEqual(definition.colors.backgroundHex, "#1A1200")
        XCTAssertEqual(definition.colors.foregroundHex, "#FFB000")
    }

    func testAmberTerminalCSSContainsCRTEffects() {
        let definition = ReaderThemeKind.amberTerminal.themeDefinition
        let css = definition.customCSS!
        XCTAssertTrue(css.contains("repeating-linear-gradient"), "Should have scanlines")
        XCTAssertTrue(css.contains("radial-gradient"), "Should have vignette")
        XCTAssertTrue(css.contains("text-shadow"), "Should have text glow")
        XCTAssertTrue(css.contains("monospace"), "Should override font to monospace")
    }

    func testAmberTerminalSyntaxCSSCoversAllTokenTypes() {
        let definition = ReaderThemeKind.amberTerminal.themeDefinition
        let css = definition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }
}
