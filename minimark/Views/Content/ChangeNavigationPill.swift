import SwiftUI

struct ChangeNavigationPill: View {
    let currentIndex: Int?
    let totalCount: Int
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private enum Metrics {
        static let pillHeight: CGFloat = 30
        static let pillInset: CGFloat = 8
        static let horizontalPadding: CGFloat = 10
        static let controlHeight: CGFloat = 28
        static let iconSize: CGFloat = 11
    }

    private var pillBorder: Color {
        Color.primary.opacity(isHovering ? 0.16 : 0.08)
    }

    var body: some View {
        HStack(spacing: 6) {
            navigationButton(
                symbolName: "chevron.up",
                label: "Previous change",
                direction: .previous
            )

            (
                Text(currentIndex.map { "\(min($0, max(0, totalCount - 1)) + 1)" } ?? "\u{2014}")
                + Text(" / \(totalCount)")
            )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            navigationButton(
                symbolName: "chevron.down",
                label: "Next change",
                direction: .next
            )
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .frame(minHeight: Metrics.pillHeight)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(pillBorder, lineWidth: 1)
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
                .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.55))
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Jumps to a changed region in the current preview")
    }
}
