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

    @Test func applyingOverrideReturnsSelfWhenOverrideIsNil() {
        let base = Theme.theme(for: .nord)
        let patched = base.applyingOverride(nil)

        #expect(patched == base)
    }

    @Test func applyingOverrideIgnoresOverrideFromDifferentThemeKind() {
        let base = Theme.theme(for: .nord)
        let override = ThemeOverride(
            themeKind: .dracula,
            backgroundHex: "#000000",
            foregroundHex: "#FFFFFF"
        )

        let patched = base.applyingOverride(override)

        #expect(patched == base)
    }

    @Test func applyingOverrideReplacesOnlyBackgroundWhenOnlyBackgroundIsSet() {
        let base = Theme.theme(for: .nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)

        let patched = base.applyingOverride(override)

        #expect(patched.backgroundHex == "#112233")
        #expect(patched.foregroundHex == base.foregroundHex)
        #expect(patched.kind == base.kind)
    }

    @Test func applyingOverrideReplacesOnlyForegroundWhenOnlyForegroundIsSet() {
        let base = Theme.theme(for: .nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: nil, foregroundHex: "#AABBCC")

        let patched = base.applyingOverride(override)

        #expect(patched.backgroundHex == base.backgroundHex)
        #expect(patched.foregroundHex == "#AABBCC")
    }

    @Test func applyingOverrideReplacesBothWhenBothAreSet() {
        let base = Theme.theme(for: .nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: "#AABBCC")

        let patched = base.applyingOverride(override)

        #expect(patched.backgroundHex == "#112233")
        #expect(patched.foregroundHex == "#AABBCC")
        #expect(patched.secondaryForegroundHex == base.secondaryForegroundHex)
        #expect(patched.linkHex == base.linkHex)
        #expect(patched.borderHex == base.borderHex)
        #expect(patched.codeBackgroundHex == base.codeBackgroundHex)
    }

    @Test func applyingOverrideIsNoOpWhenBothFieldsAreNilEvenWithMatchingKind() {
        let base = Theme.theme(for: .nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: nil, foregroundHex: nil)

        let patched = base.applyingOverride(override)

        #expect(patched == base)
    }
}
