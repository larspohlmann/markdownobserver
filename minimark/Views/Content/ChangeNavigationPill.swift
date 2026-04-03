import SwiftUI

struct ChangeNavigationPill: View {
    let currentIndex: Int
    let totalCount: Int
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    @State private var isHovering = false

    private enum Metrics {
        static let pillWidth: CGFloat = 44
        static let buttonSize: CGFloat = 32
        static let buttonCornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 12
        static let pillCornerRadius: CGFloat = 12
        static let pillInset: CGFloat = 8
        static let groupSpacing: CGFloat = 4
    }

    var body: some View {
        VStack(spacing: Metrics.groupSpacing) {
            navigationButton(
                symbolName: "arrow.up",
                label: "Previous change",
                direction: .previous
            )

            Text("\(min(currentIndex, max(0, totalCount - 1)) + 1) / \(totalCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            navigationButton(
                symbolName: "arrow.down",
                label: "Next change",
                direction: .next
            )
        }
        .padding(.vertical, Metrics.groupSpacing + 4)
        .frame(width: Metrics.pillWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovering ? 0.16 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovering ? 0.25 : 0.12), radius: isHovering ? 16 : 6, y: 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
        .padding(.top, Metrics.pillInset)
        .padding(.leading, Metrics.pillInset)
    }

    private func navigationButton(
        symbolName: String,
        label: String,
        direction: ReaderChangedRegionNavigationDirection
    ) -> some View {
        Button {
            onNavigate(direction)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: Metrics.iconSize, weight: .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Jumps to a changed region in the current preview")
    }
}
