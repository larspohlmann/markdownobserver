import AppKit
import SwiftUI

enum ColorHexConversion {
    static func hexString(from color: Color) -> String {
        let nsColor = NSColor(color)
        let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        let r = Int((srgb.redComponent * 255.0).rounded())
        let g = Int((srgb.greenComponent * 255.0).rounded())
        let b = Int((srgb.blueComponent * 255.0).rounded())
        return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    private static func clamp(_ value: Int) -> Int {
        max(0, min(255, value))
    }
}
