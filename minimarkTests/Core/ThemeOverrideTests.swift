import Foundation
import Testing
@testable import minimark

@Suite struct ThemeOverrideTests {
    @Test func themeOverrideRoundTripsFullPayload() throws {
        let override = ThemeOverride(
            themeKind: .nord,
            backgroundHex: "#112233",
            foregroundHex: "#EEDDCC"
        )

        let data = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(ThemeOverride.self, from: data)

        #expect(decoded.themeKind == .nord)
        #expect(decoded.backgroundHex == "#112233")
        #expect(decoded.foregroundHex == "#EEDDCC")
    }

    @Test func themeOverrideRoundTripsNilFields() throws {
        let override = ThemeOverride(themeKind: .blackOnWhite, backgroundHex: nil, foregroundHex: nil)
        let data = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(ThemeOverride.self, from: data)

        #expect(decoded.themeKind == .blackOnWhite)
        #expect(decoded.backgroundHex == nil)
        #expect(decoded.foregroundHex == nil)
    }
}
