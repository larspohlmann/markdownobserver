import XCTest
@testable import minimark

final class CSSFactoryCacheTests: XCTestCase {

    func testSameInputsReturnIdenticalCSS() {
        let theme = ThemeKind.blackOnWhite.themeDefinition
        let css1 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertEqual(css1, css2)
    }

    func testDifferentThemeProducesDifferentCSS() {
        let theme1 = ThemeKind.blackOnWhite.themeDefinition
        let theme2 = ThemeKind.newspaper.themeDefinition
        let css1 = CSSThemeGenerator.makeCSS(theme: theme1, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = CSSThemeGenerator.makeCSS(theme: theme2, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentFontSizeProducesDifferentCSS() {
        let theme = ThemeKind.blackOnWhite.themeDefinition
        let css1 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 20)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentSyntaxThemeProducesDifferentCSS() {
        let theme = ThemeKind.blackOnWhite.themeDefinition
        let css1 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .dracula, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }
}
