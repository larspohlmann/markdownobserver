import XCTest
@testable import minimark

final class SyntaxBackgroundAdjusterTests: XCTestCase {

    // MARK: - Identical backgrounds

    func testIdenticalDarkBackgroundsReturnBrighterHex() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#282828",
            syntaxBlockBackgroundHex: "#282828",
            isLightBackground: false
        )
        // 0x28 = 40, +8 = 48 = 0x30
        XCTAssertEqual(result, "#303030")
    }

    func testIdenticalLightBackgroundsReturnDarkerHex() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#FBF1C7",
            syntaxBlockBackgroundHex: "#FBF1C7",
            isLightBackground: true
        )
        // 0xFB=251-8=243=0xF3, 0xF1=241-8=233=0xE9, 0xC7=199-8=191=0xBF
        XCTAssertEqual(result, "#F3E9BF")
    }

    // MARK: - Near-identical backgrounds (within threshold)

    func testNearIdenticalBackgroundsWithinThresholdAdjust() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#282828",
            syntaxBlockBackgroundHex: "#2B2A28",
            isLightBackground: false
        )
        // Max delta is 3 (0x2B-0x28), within threshold of 5
        XCTAssertNotNil(result)
    }

    func testBackgroundsAtThresholdBoundaryAdjust() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#282828",
            syntaxBlockBackgroundHex: "#2D2828",
            isLightBackground: false
        )
        // Max delta is exactly 5, should still adjust
        XCTAssertNotNil(result)
    }

    // MARK: - Sufficiently different backgrounds

    func testDifferentBackgroundsReturnNil() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#282828",
            syntaxBlockBackgroundHex: "#1D2021",
            isLightBackground: false
        )
        // Max delta is 11 (0x28-0x1D), well above threshold
        XCTAssertNil(result)
    }

    func testBackgroundsJustAboveThresholdReturnNil() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#282828",
            syntaxBlockBackgroundHex: "#2E2828",
            isLightBackground: false
        )
        // Max delta is 6, above threshold of 5
        XCTAssertNil(result)
    }

    // MARK: - Real theme pairings

    func testGruvboxDarkReaderWithGruvboxDarkSyntax() {
        let reader = Theme.theme(for: .gruvboxDark)
        let syntax = SyntaxThemeKind.gruvboxDark.previewPalette
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: reader.backgroundHex,
            syntaxBlockBackgroundHex: syntax.blockBackgroundHex,
            isLightBackground: reader.hasLightBackground
        )
        XCTAssertNotNil(result, "Gruvbox Dark pairing should adjust (both #282828)")
    }

    func testMonokaiReaderWithMonokaiSyntax() {
        let reader = Theme.theme(for: .monokai)
        let syntax = SyntaxThemeKind.monokai.previewPalette
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: reader.backgroundHex,
            syntaxBlockBackgroundHex: syntax.blockBackgroundHex,
            isLightBackground: reader.hasLightBackground
        )
        XCTAssertNotNil(result, "Monokai pairing should adjust (both #272822)")
    }

    func testDraculaReaderWithDraculaSyntax() {
        let reader = Theme.theme(for: .dracula)
        let syntax = SyntaxThemeKind.dracula.previewPalette
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: reader.backgroundHex,
            syntaxBlockBackgroundHex: syntax.blockBackgroundHex,
            isLightBackground: reader.hasLightBackground
        )
        XCTAssertNotNil(result, "Dracula pairing should adjust (both #282A36)")
    }

    func testGruvboxDarkReaderWithOneDarkSyntaxNoAdjustment() {
        let reader = Theme.theme(for: .gruvboxDark)
        let syntax = SyntaxThemeKind.oneDark.previewPalette
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: reader.backgroundHex,
            syntaxBlockBackgroundHex: syntax.blockBackgroundHex,
            isLightBackground: reader.hasLightBackground
        )
        // Gruvbox Dark bg: #282828, One Dark bg: #282C34 — delta 12, no adjustment
        XCTAssertNil(result)
    }

    // MARK: - effectiveBlockBackgroundHex

    func testEffectiveHexReturnsThemePaletteForProvidesSyntaxHighlighting() {
        let theme = ThemeKind.amberTerminal.themeDefinition
        let result = SyntaxBackgroundAdjuster.effectiveBlockBackgroundHex(
            theme: theme,
            syntaxTheme: .monokai
        )
        XCTAssertEqual(result, theme.syntaxPreviewPalette?.blockBackgroundHex)
    }

    func testEffectiveHexAdjustsForMatchingNonProvidesSyntaxTheme() {
        let theme = ThemeKind.gruvboxDark.themeDefinition
        let original = SyntaxThemeKind.gruvboxDark.previewPalette.blockBackgroundHex
        let result = SyntaxBackgroundAdjuster.effectiveBlockBackgroundHex(
            theme: theme,
            syntaxTheme: .gruvboxDark
        )
        XCTAssertNotEqual(result, original, "Should adjust when backgrounds match")
    }

    func testEffectiveHexReturnsOriginalWhenBackgroundsDiffer() {
        let theme = ThemeKind.gruvboxDark.themeDefinition
        let original = SyntaxThemeKind.monokai.previewPalette.blockBackgroundHex
        let result = SyntaxBackgroundAdjuster.effectiveBlockBackgroundHex(
            theme: theme,
            syntaxTheme: .monokai
        )
        XCTAssertEqual(result, original, "Should not adjust when backgrounds differ")
    }

    // MARK: - Edge cases

    func testClampsAtBlackBoundary() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#030303",
            syntaxBlockBackgroundHex: "#030303",
            isLightBackground: true
        )
        // 3 - 8 = -5, clamped to 0
        XCTAssertEqual(result, "#000000")
    }

    func testClampsAtWhiteBoundary() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#FCFCFC",
            syntaxBlockBackgroundHex: "#FCFCFC",
            isLightBackground: false
        )
        // 252 + 8 = 260, clamped to 255
        XCTAssertEqual(result, "#FFFFFF")
    }

    func testInvalidHexReturnsNil() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "not-a-hex",
            syntaxBlockBackgroundHex: "#282828",
            isLightBackground: false
        )
        XCTAssertNil(result)
    }

    func testLowercaseHexParsesCorrectly() {
        let result = SyntaxBackgroundAdjuster.adjustedBlockBackground(
            readerBackgroundHex: "#abcdef",
            syntaxBlockBackgroundHex: "#abcdef",
            isLightBackground: true
        )
        XCTAssertNotNil(result)
    }
}
