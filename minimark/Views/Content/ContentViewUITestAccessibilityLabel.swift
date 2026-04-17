import SwiftUI

struct ContentViewUITestAccessibilityLabel: View {
    let isEnabled: Bool
    let makeValue: () -> String

    var body: some View {
        if isEnabled {
            let value = makeValue()
            Text(value)
                .font(.system(size: 8, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityIdentifier(.readerPreviewSummary)
                .accessibilityLabel("Reader preview summary")
                .accessibilityValue(value)
        }
    }
}
