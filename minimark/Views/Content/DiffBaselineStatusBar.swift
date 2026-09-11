// minimark/Views/Content/DiffBaselineStatusBar.swift
import SwiftUI

/// Bottom bar naming the snapshot the preview is compared to. Click opens a
/// menu with "Automatic" and every recorded snapshot for the current file.
struct DiffBaselineStatusBar: View {
    let state: DiffBaselineStatusBarState
    let onSelect: (DiffBaselineSelection) -> Void

    /// Fixed height of the bar. Other chrome that must clear the bar reads this.
    static let barHeight: CGFloat = 22

    private enum Metrics {
        static let height = DiffBaselineStatusBar.barHeight
        static let horizontalPadding: CGFloat = 12
        static let iconSize: CGFloat = 9
        static let labelSize: CGFloat = 10
    }

    var body: some View {
        if state.isVisible {
            HStack(spacing: 0) {
                menu
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: Metrics.height, maxHeight: Metrics.height)
            .background(.bar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(.diffBaselineStatusBar)
        }
    }

    private var menu: some View {
        Menu {
            Button {
                onSelect(.automatic)
            } label: {
                if state.isAutomatic {
                    Label(state.automaticTitle, systemImage: "checkmark")
                } else {
                    Text(state.automaticTitle)
                }
            }
            .accessibilityIdentifier(.diffBaselineAutomaticItem)

            if !state.items.isEmpty {
                Divider()
            }

            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelect(.snapshot(item.id))
                } label: {
                    if item.isActive {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
                .accessibilityIdentifier(AccessibilityID.diffBaselineSnapshotItem(index: index))
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: Metrics.iconSize, weight: .semibold))
                Text(state.label)
                    .font(.system(size: Metrics.labelSize, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!state.isEnabled)
        .help("Choose the snapshot the current version is compared to")
        .accessibilityLabel("Comparison snapshot")
        .accessibilityValue(state.label)
    }
}
