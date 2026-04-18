import SwiftUI

struct TOCOverlayView: View {
    let headings: [TOCHeading]
    let buttonAnchor: Anchor<CGRect>
    let colorScheme: ColorScheme
    let onDismiss: () -> Void
    let onSelectHeading: (TOCHeading) -> Void

    var body: some View {
        let gap: CGFloat = 8

        GeometryReader { proxy in
            let buttonFrame = proxy[buttonAnchor]
            let panelTrailing = buttonFrame.minX - gap

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                TOCPopoverView(
                    headings: headings,
                    onSelect: onSelectHeading
                )
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.25), radius: 16, y: 4)
                .colorScheme(colorScheme)
                .frame(maxWidth: panelTrailing, alignment: .trailing)
                .offset(y: buttonFrame.minY)
            }
        }
    }
}
