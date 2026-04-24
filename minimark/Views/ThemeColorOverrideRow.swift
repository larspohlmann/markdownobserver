import SwiftUI

struct ThemeColorOverrideRow: View {
    let themeKind: ThemeKind
    @Binding var override: ThemeOverride?

    private var themeDefaults: Theme { Theme.theme(for: themeKind) }

    private var effectiveBackgroundHex: String {
        (override?.themeKind == themeKind ? override?.backgroundHex : nil) ?? themeDefaults.backgroundHex
    }

    private var effectiveForegroundHex: String {
        (override?.themeKind == themeKind ? override?.foregroundHex : nil) ?? themeDefaults.foregroundHex
    }

    private var hasOverride: Bool {
        guard let override, override.themeKind == themeKind else { return false }
        return override.backgroundHex != nil || override.foregroundHex != nil
    }

    var body: some View {
        HStack(spacing: 14) {
            Text("Customize colors")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Background")
                    .foregroundStyle(.secondary)
                ColorPicker(
                    "Background",
                    selection: backgroundBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .accessibilityIdentifier("theme.override.background")
            }

            HStack(spacing: 8) {
                Text("Text")
                    .foregroundStyle(.secondary)
                ColorPicker(
                    "Text",
                    selection: foregroundBinding,
                    supportsOpacity: false
                )
                .labelsHidden()
                .accessibilityIdentifier("theme.override.foreground")
            }

            Spacer(minLength: 0)

            Button("Reset to theme defaults") {
                override = nil
            }
            .disabled(!hasOverride)
            .accessibilityIdentifier("theme.override.reset")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: effectiveBackgroundHex) ?? .clear },
            set: { setBackground($0) }
        )
    }

    private var foregroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: effectiveForegroundHex) ?? .primary },
            set: { setForeground($0) }
        )
    }

    private func setBackground(_ color: Color) {
        let hex = ColorHexConversion.hexString(from: color)
        let newBackgroundHex: String? = (hex == themeDefaults.backgroundHex) ? nil : hex
        mutateOverride { $0.backgroundHex = newBackgroundHex }
    }

    private func setForeground(_ color: Color) {
        let hex = ColorHexConversion.hexString(from: color)
        let newForegroundHex: String? = (hex == themeDefaults.foregroundHex) ? nil : hex
        mutateOverride { $0.foregroundHex = newForegroundHex }
    }

    private func mutateOverride(_ transform: (inout ThemeOverride) -> Void) {
        var working: ThemeOverride
        if let existing = override, existing.themeKind == themeKind {
            working = existing
        } else {
            working = ThemeOverride(themeKind: themeKind, backgroundHex: nil, foregroundHex: nil)
        }
        transform(&working)
        if working.backgroundHex == nil && working.foregroundHex == nil {
            override = nil
        } else {
            override = working
        }
    }
}
