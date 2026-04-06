import SwiftUI

struct TOCPopoverView: View {
    let headings: [TOCHeading]
    let onSelect: (TOCHeading) -> Void

    private enum Metrics {
        static let popoverMinWidth: CGFloat = 260
        static let popoverMaxWidth: CGFloat = 400
        static let popoverMaxHeight: CGFloat = 500
        static let rowHorizontalPadding: CGFloat = 12
        static let rowVerticalPadding: CGFloat = 5
        static let indentPerLevel: CGFloat = 16
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
        .foregroundStyle(Color(nsColor: .labelColor))
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
