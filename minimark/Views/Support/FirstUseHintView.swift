import SwiftUI

struct FirstUseHintView: View {
    let hint: FirstUseHint
    let message: String
    let settingsStore: ReaderSettingsStore

    var body: some View {
        if !settingsStore.isHintDismissed(hint) {
            HStack(spacing: 4) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    withAnimation {
                        settingsStore.dismissHint(hint)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss hint")
            }
            .fixedSize()
            .transition(.opacity)
        }
    }
}
