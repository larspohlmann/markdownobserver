import AppKit

final class DockTileBadgeView: NSView {
    struct Counts: Equatable {
        var created: Int
        var modified: Int
        var deleted: Int

        var isEmpty: Bool { created == 0 && modified == 0 && deleted == 0 }
    }

    var counts = Counts(created: 0, modified: 0, deleted: 0) {
        didSet {
            if counts != oldValue {
                needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let appIcon = NSApp?.applicationIconImage else { return }
        appIcon.draw(in: bounds)

        guard !counts.isEmpty else { return }

        let bubbleDiameter: CGFloat = 24
        let bubbleSpacing: CGFloat = 3
        let borderWidth: CGFloat = 2
        let fontSize: CGFloat = 11

        let activeBubbles: [(color: NSColor, count: Int)] = [
            (.systemGreen, counts.created),
            (.systemYellow, counts.modified),
            (.systemRed, counts.deleted),
        ].filter { $0.count > 0 }

        let totalWidth = CGFloat(activeBubbles.count) * bubbleDiameter
            + CGFloat(max(activeBubbles.count - 1, 0)) * bubbleSpacing

        let startX = bounds.maxX - totalWidth - 2
        let centerY = bounds.maxY - bubbleDiameter / 2 - 2

        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        for (index, bubble) in activeBubbles.enumerated() {
            let centerX = startX + CGFloat(index) * (bubbleDiameter + bubbleSpacing) + bubbleDiameter / 2
            let bubbleRect = NSRect(
                x: centerX - bubbleDiameter / 2,
                y: centerY - bubbleDiameter / 2,
                width: bubbleDiameter,
                height: bubbleDiameter
            )

            // White border
            let borderPath = NSBezierPath(ovalIn: bubbleRect)
            NSColor.white.setFill()
            borderPath.fill()

            // Colored fill
            let insetRect = bubbleRect.insetBy(dx: borderWidth, dy: borderWidth)
            let fillPath = NSBezierPath(ovalIn: insetRect)
            bubble.color.setFill()
            fillPath.fill()

            // Count text
            let text = "\(bubble.count)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle,
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = NSRect(
                x: centerX - textSize.width / 2,
                y: centerY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
