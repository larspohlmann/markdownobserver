import AppKit

@MainActor
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

        let activeBubbles: [(fill: NSColor, text: NSColor, count: Int)] = [
            (NSColor(red: 0.20, green: 0.70, blue: 0.30, alpha: 1), .white, counts.created),
            (NSColor(red: 0.90, green: 0.72, blue: 0.15, alpha: 1), NSColor(red: 0.25, green: 0.20, blue: 0.05, alpha: 1), counts.modified),
            (NSColor(red: 0.85, green: 0.20, blue: 0.18, alpha: 1), .white, counts.deleted),
        ].filter { $0.count > 0 }

        let padding: CGFloat = 4
        let bubbleSpacing: CGFloat = 4
        let bubbleCount = CGFloat(activeBubbles.count)
        let availableWidth = bounds.width - 2 * padding
        let bubbleDiameter = min(42, (availableWidth - (bubbleCount - 1) * bubbleSpacing) / bubbleCount)
        let borderWidth: CGFloat = 2.5
        let fontSize = bubbleDiameter * 0.57

        let totalWidth = bubbleCount * bubbleDiameter + (bubbleCount - 1) * bubbleSpacing
        let startX = bounds.maxX - totalWidth - padding
        let centerY = bounds.maxY - bubbleDiameter / 2 - padding

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
            bubble.fill.setFill()
            fillPath.fill()

            // Count text
            let text = "\(bubble.count)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: bubble.text,
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
