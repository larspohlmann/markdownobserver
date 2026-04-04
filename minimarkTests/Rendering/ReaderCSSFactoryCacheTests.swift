import XCTest
@testable import minimark

@MainActor
final class ReaderCSSFactoryCacheTests: XCTestCase {

    func testSameInputsReturnIdenticalCSS() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertEqual(css1, css2)
    }

    func testDifferentThemeProducesDifferentCSS() {
        let theme1 = ReaderThemeKind.blackOnWhite.themeDefinition
        let theme2 = ReaderThemeKind.newspaper.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme1, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme2, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentFontSizeProducesDifferentCSS() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 20)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentSyntaxThemeProducesDifferentCSS() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .dracula, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }
}
