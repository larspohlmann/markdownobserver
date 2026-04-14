import Foundation

/// Nudges the syntax code-block background when it is nearly identical to
/// the reader page background, so code blocks remain visually distinct.
///
/// Dark themes: code-block background becomes slightly brighter.
/// Light themes: code-block background becomes slightly darker.
enum SyntaxBackgroundAdjuster {

    private static let maxChannelDelta = 5
    private static let adjustmentStep = 8

    /// Returns the effective code-block background hex for a given theme
    /// and syntax theme combination. Adjusts when the two backgrounds are
    /// too close; returns the original syntax background otherwise.
    /// Themes that provide their own syntax highlighting are never adjusted.
    static func effectiveBlockBackgroundHex(
        theme: ThemeDefinition,
        syntaxTheme: SyntaxThemeKind
    ) -> String {
        if theme.providesSyntaxHighlighting {
            return theme.syntaxPreviewPalette?.blockBackgroundHex
                ?? syntaxTheme.previewPalette.blockBackgroundHex
        }

        let palette = syntaxTheme.previewPalette
        if let adjusted = adjustedBlockBackground(
               readerBackgroundHex: theme.colors.backgroundHex,
               syntaxBlockBackgroundHex: palette.blockBackgroundHex,
               isLightBackground: theme.colors.hasLightBackground
           ) {
            return adjusted
        }
        return palette.blockBackgroundHex
    }

    /// Returns an adjusted hex colour string when the two backgrounds are
    /// too close, or `nil` when no adjustment is needed.
    static func adjustedBlockBackground(
        readerBackgroundHex: String,
        syntaxBlockBackgroundHex: String,
        isLightBackground: Bool
    ) -> String? {
        guard let readerRGB = parseHex(readerBackgroundHex),
              let syntaxRGB = parseHex(syntaxBlockBackgroundHex) else {
            return nil
        }

        let maxDiff = max(
            abs(readerRGB.r - syntaxRGB.r),
            abs(readerRGB.g - syntaxRGB.g),
            abs(readerRGB.b - syntaxRGB.b)
        )

        guard maxDiff <= maxChannelDelta else { return nil }

        let step = isLightBackground ? -adjustmentStep : adjustmentStep
        let adjusted = (
            r: clamp(syntaxRGB.r + step),
            g: clamp(syntaxRGB.g + step),
            b: clamp(syntaxRGB.b + step)
        )

        return String(format: "#%02X%02X%02X", adjusted.r, adjusted.g, adjusted.b)
    }

    // MARK: - Hex parsing

    private static func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6, let value = UInt32(clean, radix: 16) else { return nil }
        return (
            r: Int((value >> 16) & 0xFF),
            g: Int((value >> 8) & 0xFF),
            b: Int(value & 0xFF)
        )
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 255)
    }
}
