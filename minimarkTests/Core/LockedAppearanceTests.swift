import XCTest
@testable import minimark

final class LockedAppearanceTests: XCTestCase {
    func testLockedAppearanceCapturesAllThreeProperties() {
        let appearance = LockedAppearance(
            readerTheme: .newspaper,
            baseFontSize: 18,
            syntaxTheme: .dracula
        )

        XCTAssertEqual(appearance.readerTheme, .newspaper)
        XCTAssertEqual(appearance.baseFontSize, 18)
        XCTAssertEqual(appearance.syntaxTheme, .dracula)
    }

    func testLockedAppearanceEquality() {
        let a = LockedAppearance(readerTheme: .newspaper, baseFontSize: 18, syntaxTheme: .dracula)
        let b = LockedAppearance(readerTheme: .newspaper, baseFontSize: 18, syntaxTheme: .dracula)
        let c = LockedAppearance(readerTheme: .focus, baseFontSize: 18, syntaxTheme: .dracula)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testLockedAppearanceRoundTripsThroughJSON() throws {
        let original = LockedAppearance(
            readerTheme: .greenTerminal,
            baseFontSize: 24,
            syntaxTheme: .nord
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LockedAppearance.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
