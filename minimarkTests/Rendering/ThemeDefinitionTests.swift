import XCTest
@testable import minimark

final class ThemeDefinitionTests: XCTestCase {

    func testSimpleThemeDefinitionHasNilCustomCSS() {
        let definition = ReaderThemeKind.blackOnWhite.themeDefinition
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertNil(definition.syntaxCSS)
        XCTAssertFalse(definition.providesSyntaxHighlighting)
    }

    func testSimpleThemeDefinitionHasCorrectColors() {
        let definition = ReaderThemeKind.blackOnWhite.themeDefinition
        let expectedColors = ReaderTheme.theme(for: .blackOnWhite)
        XCTAssertEqual(definition.colors, expectedColors)
        XCTAssertEqual(definition.kind, .blackOnWhite)
        XCTAssertEqual(definition.displayName, "White background / Black text")
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
            XCTAssertFalse(definition.providesSyntaxHighlighting, "Simple theme \(kind) should not provide syntax highlighting")
        }
    }
}
