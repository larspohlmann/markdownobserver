import Foundation
import Testing
@testable import minimark

@Suite struct CSSThemeGeneratorOverrideTests {
    @Test func cssReflectsBackgroundOverride() {
        let theme = ThemeKind.nord.themeDefinition
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)

        let css = CSSThemeGenerator.makeCSS(
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: override
        )

        #expect(css.contains("--reader-bg: #112233;"))
        #expect(css.contains("--reader-fg: \(theme.colors.foregroundHex);"))
    }

    @Test func cssReflectsForegroundOverride() {
        let theme = ThemeKind.nord.themeDefinition
        let override = ThemeOverride(themeKind: .nord, backgroundHex: nil, foregroundHex: "#AABBCC")

        let css = CSSThemeGenerator.makeCSS(
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: override
        )

        #expect(css.contains("--reader-fg: #AABBCC;"))
        #expect(css.contains("--reader-bg: \(theme.colors.backgroundHex);"))
    }

    @Test func cssIgnoresOverrideFromDifferentThemeKind() {
        let theme = ThemeKind.nord.themeDefinition
        let override = ThemeOverride(themeKind: .dracula, backgroundHex: "#000000", foregroundHex: "#FFFFFF")

        let css = CSSThemeGenerator.makeCSS(
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: override
        )

        #expect(css.contains("--reader-bg: \(theme.colors.backgroundHex);"))
        #expect(css.contains("--reader-fg: \(theme.colors.foregroundHex);"))
    }

    @Test func cacheDoesNotMixOverriddenAndPlainOutputs() {
        let theme = ThemeKind.nord.themeDefinition

        let plain = CSSThemeGenerator.makeCSS(
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        )
        let overridden = CSSThemeGenerator.makeCSS(
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)
        )

        #expect(plain != overridden)
        #expect(plain.contains("--reader-bg: \(theme.colors.backgroundHex);"))
        #expect(overridden.contains("--reader-bg: #112233;"))
    }
}
