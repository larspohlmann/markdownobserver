import AppKit
import SwiftUI
import Testing
@testable import minimark

@Suite struct ColorHexConversionTests {
    @Test func hexStringFromColorRoundTripsSixDigitUppercase() {
        let color = Color(red: 0x11 / 255.0, green: 0x22 / 255.0, blue: 0x33 / 255.0)
        let hex = ColorHexConversion.hexString(from: color)
        #expect(hex == "#112233")
    }

    @Test func hexStringNormalizesSaturatedWhite() {
        let hex = ColorHexConversion.hexString(from: .white)
        #expect(hex == "#FFFFFF")
    }

    @Test func hexStringNormalizesSaturatedBlack() {
        let hex = ColorHexConversion.hexString(from: .black)
        #expect(hex == "#000000")
    }

    @Test func hexStringRoundTripsThroughColorInit() throws {
        let expected = "#4A89DC"
        let color = try #require(Color(hex: expected))

        let hex = ColorHexConversion.hexString(from: color)

        let original = try #require(Color(hex: expected))
        let roundTripped = try #require(Color(hex: hex))
        let nsOriginal = NSColor(original).usingColorSpace(.sRGB) ?? NSColor(original)
        let nsRoundTripped = NSColor(roundTripped).usingColorSpace(.sRGB) ?? NSColor(roundTripped)
        let tolerance: Double = 1.0 / 255.0
        #expect(abs(nsOriginal.redComponent - nsRoundTripped.redComponent) <= tolerance)
        #expect(abs(nsOriginal.greenComponent - nsRoundTripped.greenComponent) <= tolerance)
        #expect(abs(nsOriginal.blueComponent - nsRoundTripped.blueComponent) <= tolerance)
    }
}
