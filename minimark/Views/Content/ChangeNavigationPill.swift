import SwiftUI

struct ChangeNavigationPill: View {
    let currentIndex: Int?
    let totalCount: Int
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    fileprivate enum Metrics {
        static let pillHeight: CGFloat = 30
        static let horizontalPadding: CGFloat = 10
        static let controlHeight: CGFloat = 28
        static let iconSize: CGFloat = 11
    }

    private var pillBorder: Color {
        Color.primary.opacity(isHovering ? 0.16 : 0.08)
    }

    var body: some View {
        HStack(spacing: 6) {
            NavigationChevronButton(
                symbolName: "chevron.up",
                label: "Previous change",
                direction: .previous,
                onNavigate: onNavigate
            )

            (
                Text(currentIndex.map { "\(min($0, max(0, totalCount - 1)) + 1)" } ?? "\u{2014}")
                + Text(" / \(totalCount)")
            )
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            NavigationChevronButton(
                symbolName: "chevron.down",
                label: "Next change",
                direction: .next,
                onNavigate: onNavigate
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
        .fixedSize()
    }

}

private struct NavigationChevronButton: View {
    let symbolName: String
    let label: String
    let direction: ReaderChangedRegionNavigationDirection
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onNavigate(direction)
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: ChangeNavigationPill.Metrics.iconSize, weight: .semibold))
                .frame(width: ChangeNavigationPill.Metrics.controlHeight, height: ChangeNavigationPill.Metrics.controlHeight)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(isHovered ? 0.75 : 0.55))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Jumps to a changed region in the current preview")
    }
}
