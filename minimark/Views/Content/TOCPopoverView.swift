import SwiftUI

struct TOCPopoverView: View {
    let headings: [TOCHeading]
    let onSelect: (TOCHeading) -> Void
    @State private var hoveredHeadingID: Int?

    private enum Metrics {
        static let popoverMinWidth: CGFloat = 320
        static let popoverMaxWidth: CGFloat = 480
        static let popoverMaxHeight: CGFloat = 600
        static let rowHorizontalPadding: CGFloat = 14
        static let rowVerticalPadding: CGFloat = 6
        static let indentPerLevel: CGFloat = 18
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(headings) { heading in
                    Button {
                        onSelect(heading)
                    } label: {
                        Text(heading.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .font(headingFont(for: heading.level))
                            .foregroundStyle(headingForegroundStyle(for: heading.level))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Metrics.rowHorizontalPadding + CGFloat(heading.level - 1) * Metrics.indentPerLevel)
                            .padding(.trailing, Metrics.rowHorizontalPadding)
                            .padding(.vertical, Metrics.rowVerticalPadding)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(hoveredHeadingID == heading.id ? Color.primary.opacity(0.06) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(PointingHandCursor())
                    .onHover { isHovered in
                        if isHovered {
                            hoveredHeadingID = heading.id
                        } else if hoveredHeadingID == heading.id {
                            hoveredHeadingID = nil
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.12), value: hoveredHeadingID)
            .padding(.vertical, 8)
        }
        .frame(minWidth: Metrics.popoverMinWidth, maxWidth: Metrics.popoverMaxWidth, maxHeight: Metrics.popoverMaxHeight)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 14, weight: .bold)
        case 2:
            return .system(size: 13, weight: .semibold)
        default:
            return .system(size: 12, weight: .regular)
        }
    }

    private func headingForegroundStyle(for level: Int) -> some ShapeStyle {
        switch level {
        case 1:
            return AnyShapeStyle(.primary)
        case 2:
            return AnyShapeStyle(.primary.opacity(0.85))
        default:
            return AnyShapeStyle(.secondary)
        }
    }
}
