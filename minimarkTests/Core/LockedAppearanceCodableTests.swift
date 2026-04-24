import Foundation
import Testing
@testable import minimark

@Suite struct LockedAppearanceCodableTests {
    @Test func lockedAppearanceRoundTripsWithOverride() throws {
        let locked = LockedAppearance(
            readerTheme: .nord,
            baseFontSize: 16,
            syntaxTheme: .monokai,
            readerThemeOverride: ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: "#AABBCC")
        )

        let data = try JSONEncoder().encode(locked)
        let decoded = try JSONDecoder().decode(LockedAppearance.self, from: data)

        #expect(decoded == locked)
    }

    @Test func lockedAppearanceRoundTripsWithoutOverride() throws {
        let locked = LockedAppearance(
            readerTheme: .nord,
            baseFontSize: 16,
            syntaxTheme: .monokai,
            readerThemeOverride: nil
        )

        let data = try JSONEncoder().encode(locked)
        let decoded = try JSONDecoder().decode(LockedAppearance.self, from: data)

        #expect(decoded == locked)
    }

    @Test func lockedAppearanceLegacyPayloadDecodesOverrideAsNil() throws {
        let legacy: [String: Any] = [
            "readerTheme": "nord",
            "baseFontSize": 16,
            "syntaxTheme": "monokai"
        ]
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let decoded = try JSONDecoder().decode(LockedAppearance.self, from: data)

        #expect(decoded.readerTheme == .nord)
        #expect(decoded.baseFontSize == 16)
        #expect(decoded.syntaxTheme == .monokai)
        #expect(decoded.readerThemeOverride == nil)
    }
}
