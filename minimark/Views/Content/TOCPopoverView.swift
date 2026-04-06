import SwiftUI

struct TOCPopoverView: View {
    let headings: [TOCHeading]
    let onSelect: (TOCHeading) -> Void

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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Metrics.rowHorizontalPadding + CGFloat(heading.level - 1) * Metrics.indentPerLevel)
                            .padding(.trailing, Metrics.rowHorizontalPadding)
                            .padding(.vertical, Metrics.rowVerticalPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(PointingHandCursor())
                }
            }
            .padding(.vertical, 8)
        }
        .font(.system(size: 13))
        .frame(minWidth: Metrics.popoverMinWidth, maxWidth: Metrics.popoverMaxWidth, maxHeight: Metrics.popoverMaxHeight)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 13, weight: .semibold)
        default:
            return .system(size: 13)
        }
    }
}
