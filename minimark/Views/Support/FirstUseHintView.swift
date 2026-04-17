import SwiftUI

struct FirstUseHintModifier: ViewModifier {
    let hint: FirstUseHint
    let message: String
    let settingsStore: SettingsStore
    let isActive: Bool

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss hint")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: isActive) { _, active in
                if active && !settingsStore.isHintDismissed(hint) {
                    isPresented = true
                }
            }
            .onChange(of: isPresented) { _, newValue in
                if !newValue {
                    settingsStore.dismissHint(hint)
                }
            }
            .onAppear {
                if isActive && !settingsStore.isHintDismissed(hint) {
                    isPresented = true
                }
            }
    }
}

extension View {
    func firstUseHint(
        _ hint: FirstUseHint,
        message: String,
        settingsStore: SettingsStore,
        isActive: Bool = true
    ) -> some View {
        modifier(FirstUseHintModifier(hint: hint, message: message, settingsStore: settingsStore, isActive: isActive))
    }
}

