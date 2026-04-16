import SwiftUI

struct ContentViewUITestAccessibilityLabel: View {
    let isEnabled: Bool
    let value: String

    var body: some View {
        if isEnabled {
            Text(value)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityIdentifier("reader-preview-summary")
                .accessibilityLabel("Reader preview summary")
                .accessibilityValue(value)
        }
    }
}
