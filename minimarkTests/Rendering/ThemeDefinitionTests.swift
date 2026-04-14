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

    // MARK: - CSS Layer Composition

    func testSimpleThemeCSSDoesNotContainCustomCSS() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("--reader-bg:"))
        XCTAssertTrue(css.contains(".hljs-keyword"), "Should contain syntax theme CSS from SyntaxThemeKind")
        XCTAssertFalse(css.contains("Amber Terminal"), "Should not contain amber custom CSS")
    }

    func testAmberTerminalCSSIncludesCustomCSSAfterStructural() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.amberTerminal.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)

        XCTAssertTrue(css.contains("--reader-bg:"), "Should contain CSS variables")
        XCTAssertTrue(css.contains("repeating-linear-gradient"), "Should contain scanlines from customCSS")
        XCTAssertTrue(css.contains("radial-gradient"), "Should contain vignette from customCSS")

        // Custom CSS should appear after structural CSS
        let structuralRange = css.range(of: ".markdown-body")!
        let customRange = css.range(of: "Amber Terminal CRT Theme")!
        XCTAssertTrue(customRange.lowerBound > structuralRange.lowerBound,
                       "Custom CSS should appear after structural CSS")
    }

    func testAmberTerminalUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.amberTerminal.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)

        // Should contain amber syntax tokens, not Monokai ones
        XCTAssertTrue(css.contains("color: #FFB000"), "Should contain amber syntax CSS")
        XCTAssertFalse(css.contains("#F92672"), "Should not contain Monokai keyword color")
    }

    func testSimpleThemeUsesSelectedSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)

        XCTAssertTrue(css.contains("#F92672"), "Should contain Monokai keyword color")
    }

    // MARK: - Green Terminal Static Theme

    func testGreenTerminalStaticHasNoJavaScript() {
        let definition = ReaderThemeKind.greenTerminalStatic.themeDefinition
        XCTAssertNil(definition.customJavaScript)
        XCTAssertNotNil(definition.customCSS)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertEqual(definition.colors.backgroundHex, "#0D0208")
        XCTAssertEqual(definition.displayName, "Green Terminal (Static)")
    }

    // MARK: - JS Injection

    func testHTMLDocumentIncludesThemeJSMetaAndBootstrapWhenProvided() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: nil,
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil
            ),
            themeJavaScript: "console.log('theme loaded');"
        )
        XCTAssertTrue(html.contains("minimark-runtime-theme-js-base64"), "Should include theme JS meta tag")
        XCTAssertTrue(html.contains("__minimarkLastThemeJSBase64"), "Should include bootstrap script")
    }

    func testHTMLDocumentOmitsThemeJSMetaWhenNil() {
        let factory = ReaderCSSFactory()
        let html = factory.makeHTMLDocument(
            css: "",
            payloadBase64: "",
            runtimeAssets: ReaderRuntimeAssets(
                markdownItScriptPath: "markdown-it.min.js",
                highlightScriptPath: nil,
                taskListsScriptPath: nil,
                footnoteScriptPath: nil,
                attrsScriptPath: nil,
                deflistScriptPath: nil
            )
        )
        XCTAssertFalse(html.contains("minimark-runtime-theme-js-base64"), "Should not include theme JS meta tag")
        XCTAssertFalse(html.contains("__minimarkLastThemeJSBase64"), "Should not include bootstrap script")
    }

    // MARK: - Green Terminal Theme

    func testGreenTerminalHasCorrectDisplayName() {
        let kind = ReaderThemeKind.greenTerminal
        XCTAssertEqual(kind.displayName, "Green Terminal")
        XCTAssertTrue(kind.isDark)
    }

    func testGreenTerminalDefinitionProvidesAllCustomFields() {
        let definition = ReaderThemeKind.greenTerminal.themeDefinition
        XCTAssertNotNil(definition.customCSS)
        XCTAssertNotNil(definition.customJavaScript, "Green Terminal should have digital rain JS")
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testGreenTerminalColorsAreGreenPalette() {
        let definition = ReaderThemeKind.greenTerminal.themeDefinition
        XCTAssertFalse(definition.colors.hasLightBackground)
        XCTAssertEqual(definition.colors.backgroundHex, "#0D0208")
        XCTAssertEqual(definition.colors.foregroundHex, "#00FF41")
    }

    func testGreenTerminalCSSContainsCRTEffects() {
        let definition = ReaderThemeKind.greenTerminal.themeDefinition
        let css = definition.customCSS!
        XCTAssertTrue(css.contains("repeating-linear-gradient"), "Should have scanlines")
        XCTAssertTrue(css.contains("radial-gradient"), "Should have vignette")
        XCTAssertTrue(css.contains("text-shadow"), "Should have text glow")
        XCTAssertTrue(css.contains("monospace"), "Should override font to monospace")
        XCTAssertTrue(css.contains("rgba(0, 255, 65"), "Glow should use green, not amber")
    }

    func testGreenTerminalSyntaxCSSCoversAllTokenTypes() {
        let definition = ReaderThemeKind.greenTerminal.themeDefinition
        let css = definition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    func testGreenTerminalJSContainsDigitalRain() {
        let definition = ReaderThemeKind.greenTerminal.themeDefinition
        let js = definition.customJavaScript!
        XCTAssertTrue(js.contains("canvas"), "Should create a canvas element")
        XCTAssertTrue(js.contains("__minimarkThemeCleanup"), "Should register cleanup hook")
        XCTAssertTrue(js.contains("ﾊﾐﾋ"), "Should contain katakana characters")
        XCTAssertTrue(js.contains("prefers-reduced-motion"), "Should respect reduced motion")
    }

    func testGreenTerminalUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.greenTerminal.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)

        XCTAssertTrue(css.contains("color: #00FF41"), "Should contain green syntax CSS")
        XCTAssertFalse(css.contains("#F92672"), "Should not contain Monokai keyword color")
    }

    // MARK: - Newspaper Theme

    func testNewspaperThemeDefinition() {
        let definition = ReaderThemeKind.newspaper.themeDefinition
        XCTAssertEqual(definition.displayName, "Newspaper")
        XCTAssertFalse(definition.kind.isDark)
        XCTAssertNotNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
        XCTAssertNil(definition.syntaxCSS)
    }

    func testNewspaperCSSContainsSerifTypography() {
        let css = ReaderThemeKind.newspaper.themeDefinition.customCSS!
        XCTAssertTrue(css.contains("Charter"))
        XCTAssertTrue(css.contains("Georgia"))
        XCTAssertTrue(css.contains("serif"))
        XCTAssertTrue(css.contains("border-bottom"))
    }

    // MARK: - Focus Theme

    func testFocusThemeDefinition() {
        let definition = ReaderThemeKind.focus.themeDefinition
        XCTAssertEqual(definition.displayName, "Focus")
        XCTAssertFalse(definition.kind.isDark)
        XCTAssertNotNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
    }

    func testFocusCSSContainsGenerousLineHeight() {
        let css = ReaderThemeKind.focus.themeDefinition.customCSS!
        XCTAssertTrue(css.contains("line-height: 1.8"))
        XCTAssertTrue(css.contains("text-decoration: underline"))
    }

    // MARK: - Commodore 64 Theme

    func testCommodore64ThemeDefinition() {
        let definition = ReaderThemeKind.commodore64.themeDefinition
        XCTAssertEqual(definition.displayName, "Commodore 64")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNotNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testCommodore64ColorsAreC64Palette() {
        let definition = ReaderThemeKind.commodore64.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#40318D")
        XCTAssertEqual(definition.colors.linkHex, "#FFFFFF")
    }

    func testCommodore64SyntaxCSSCoversAllTokenTypes() {
        let css = ReaderThemeKind.commodore64.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    // MARK: - Game Boy Theme

    func testGameBoyThemeDefinition() {
        let definition = ReaderThemeKind.gameBoy.themeDefinition
        XCTAssertEqual(definition.displayName, "Game Boy")
        XCTAssertFalse(definition.kind.isDark)
        XCTAssertNotNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testGameBoyUsesAuthenticDMGPalette() {
        let definition = ReaderThemeKind.gameBoy.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#9BBC0F")
        XCTAssertEqual(definition.colors.foregroundHex, "#0F380F")
    }

    func testGameBoyCSSContainsPixelGrid() {
        let css = ReaderThemeKind.gameBoy.themeDefinition.customCSS!
        XCTAssertTrue(css.contains("background-image"), "Should have pixel grid overlay")
        XCTAssertTrue(css.contains("monospace"))
    }

    func testGameBoySyntaxUsesOnly4Shades() {
        let css = ReaderThemeKind.gameBoy.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains("#0F380F"), "Should use darkest shade")
        XCTAssertTrue(css.contains("#306230"), "Should use dark shade")
        XCTAssertTrue(css.contains("font-weight: bold"), "Should use weight to differentiate")
    }

    // MARK: - Theme Color Scheme Consistency

    func testIsDarkAndHasLightBackgroundAreConsistentForAllThemes() {
        for kind in ReaderThemeKind.allCases {
            let theme = ReaderTheme.theme(for: kind)
            XCTAssertEqual(
                kind.isDark, !theme.hasLightBackground,
                "\(kind): isDark (\(kind.isDark)) must be opposite of hasLightBackground (\(theme.hasLightBackground))"
            )
        }
    }

    // MARK: - Backward Compatibility

    func testSimpleThemesCSSOutputContainsExpectedVariables() {
        let factory = ReaderCSSFactory()
        for kind in [ReaderThemeKind.blackOnWhite, .whiteOnBlack, .darkGreyOnLightGrey, .lightGreyOnDarkGrey] {
            let theme = kind.themeDefinition
            let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
            let expectedColors = ReaderTheme.theme(for: kind)
            XCTAssertTrue(css.contains(expectedColors.backgroundHex), "CSS should contain background hex for \(kind)")
            XCTAssertTrue(css.contains(expectedColors.foregroundHex), "CSS should contain foreground hex for \(kind)")
        }
    }

    // MARK: - New Content Themes

    func testGruvboxDarkThemeDefinition() {
        let definition = ReaderThemeKind.gruvboxDark.themeDefinition
        XCTAssertEqual(definition.displayName, "Gruvbox Dark")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertNil(definition.syntaxPreviewPalette)
    }

    func testGruvboxDarkColors() {
        let definition = ReaderThemeKind.gruvboxDark.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#282828")
        XCTAssertEqual(definition.colors.foregroundHex, "#EBDBB2")
        XCTAssertEqual(definition.colors.linkHex, "#FE8019")
        XCTAssertEqual(definition.colors.h1Hex, "#FB4934")
        XCTAssertEqual(definition.colors.h2Hex, "#B8BB26")
        XCTAssertEqual(definition.colors.h3Hex, "#83A598")
    }

    func testGruvboxLightThemeDefinition() {
        let definition = ReaderThemeKind.gruvboxLight.themeDefinition
        XCTAssertEqual(definition.displayName, "Gruvbox Light")
        XCTAssertFalse(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertNil(definition.syntaxPreviewPalette)
    }

    func testGruvboxLightColors() {
        let definition = ReaderThemeKind.gruvboxLight.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#FBF1C7")
        XCTAssertEqual(definition.colors.foregroundHex, "#3C3836")
        XCTAssertEqual(definition.colors.linkHex, "#076678")
        XCTAssertEqual(definition.colors.h1Hex, "#9D0006")
        XCTAssertEqual(definition.colors.h2Hex, "#79740E")
        XCTAssertEqual(definition.colors.h3Hex, "#076678")
    }

    func testDraculaThemeDefinition() {
        let definition = ReaderThemeKind.dracula.themeDefinition
        XCTAssertEqual(definition.displayName, "Dracula")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertNil(definition.syntaxPreviewPalette)
    }

    func testDraculaColors() {
        let definition = ReaderThemeKind.dracula.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#282A36")
        XCTAssertEqual(definition.colors.foregroundHex, "#F8F8F2")
        XCTAssertEqual(definition.colors.linkHex, "#8BE9FD")
        XCTAssertEqual(definition.colors.h1Hex, "#FF79C6")
        XCTAssertEqual(definition.colors.h2Hex, "#50FA7B")
        XCTAssertEqual(definition.colors.h3Hex, "#8BE9FD")
    }

    func testMonokaiThemeDefinition() {
        let definition = ReaderThemeKind.monokai.themeDefinition
        XCTAssertEqual(definition.displayName, "Monokai")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertNil(definition.syntaxPreviewPalette)
    }

    func testMonokaiColors() {
        let definition = ReaderThemeKind.monokai.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#272822")
        XCTAssertEqual(definition.colors.foregroundHex, "#F8F8F2")
        XCTAssertEqual(definition.colors.linkHex, "#A6E22E")
        XCTAssertEqual(definition.colors.h1Hex, "#F92672")
        XCTAssertEqual(definition.colors.h2Hex, "#A6E22E")
        XCTAssertEqual(definition.colors.h3Hex, "#66D9EF")
    }

    func testNewThemesCSSContainsHeaderVariables() {
        let factory = ReaderCSSFactory()
        let newThemes: [ReaderThemeKind] = [.gruvboxDark, .gruvboxLight, .dracula, .monokai]
        for kind in newThemes {
            let theme = kind.themeDefinition
            let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
            let colors = theme.colors
            XCTAssertTrue(css.contains("--reader-h1: \(colors.h1Hex!)"), "Missing h1 variable for \(kind)")
            XCTAssertTrue(css.contains("--reader-h2: \(colors.h2Hex!)"), "Missing h2 variable for \(kind)")
            XCTAssertTrue(css.contains("--reader-h3: \(colors.h3Hex!)"), "Missing h3 variable for \(kind)")
        }
    }

    func testNewThemesUseSelectedSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.gruvboxDark.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
        XCTAssertTrue(css.contains("#D73A49"), "Should contain GitHub keyword color from selected syntax theme")
    }

    func testSimpleThemesDoNotEmitHeaderVariables() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertFalse(css.contains("--reader-h1:"), "Simple themes should not emit h1 variable")
        XCTAssertFalse(css.contains("--reader-h2:"), "Simple themes should not emit h2 variable")
        XCTAssertFalse(css.contains("--reader-h3:"), "Simple themes should not emit h3 variable")
    }

    func testHeaderColorFallbackInCSS() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: var(--reader-h1, var(--reader-fg))"), "h1 should fall back to foreground")
        XCTAssertTrue(css.contains("color: var(--reader-h2, var(--reader-fg))"), "h2 should fall back to foreground")
        XCTAssertTrue(css.contains("color: var(--reader-h3, var(--reader-fg))"), "h3 should fall back to foreground")
    }
}
