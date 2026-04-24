import Combine
import SwiftUI

struct ThemeColorOverrideRow: View {
    let themeKind: ThemeKind
    @Binding var override: ThemeOverride?

    private var themeDefaults: Theme { Theme.theme(for: themeKind) }

    private var matchedOverride: ThemeOverride? {
        override?.themeKind == themeKind ? override : nil
    }

    private var effectiveBackgroundHex: String {
        matchedOverride?.backgroundHex ?? themeDefaults.backgroundHex
    }

    private var effectiveForegroundHex: String {
        matchedOverride?.foregroundHex ?? themeDefaults.foregroundHex
    }

    private var hasOverride: Bool {
        guard let matched = matchedOverride else { return false }
        return matched.backgroundHex != nil || matched.foregroundHex != nil
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
        .background(
            GeometryReader { geo in
                Color.clear
                    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                        guard let panel = notification.object as? NSWindow,
                              panel === NSColorPanel.shared else { return }
                        let rowFrame = geo.frame(in: .global)
                        let panelSize = panel.frame.size
                        panel.setFrameOrigin(NSPoint(
                            x: rowFrame.maxX + 12,
                            y: rowFrame.midY - panelSize.height / 2
                        ))
                    }
            }
        )
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
        var working = matchedOverride ?? ThemeOverride(themeKind: themeKind, backgroundHex: nil, foregroundHex: nil)
        transform(&working)
        override = (working.backgroundHex == nil && working.foregroundHex == nil) ? nil : working
    }
}
