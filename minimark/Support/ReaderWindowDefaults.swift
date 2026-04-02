import AppKit
import CoreGraphics

enum ReaderWindowDefaults {
    static let letterAspectRatio: CGFloat = 11.0 / 8.5
    static let baseWidth: CGFloat = 1100
    static let baseHeight: CGFloat = baseWidth * letterAspectRatio
    static let minimumUsableWidth: CGFloat = 640
    static let fittedHeightUsage: CGFloat = 0.9
    static let minimumUsableHeightTolerance: CGFloat = 0.96

    static var defaultWidth: CGFloat {
        defaultSize.width
    }

    static var defaultHeight: CGFloat {
        defaultSize.height
    }

    static var defaultSize: CGSize {
        guard let visibleFrame = preferredVisibleFrame else {
            return CGSize(width: baseWidth, height: baseHeight)
        }

        return size(forVisibleFrame: visibleFrame)
    }

    static func size(forVisibleFrame visibleFrame: CGRect) -> CGSize {
        let fittedSize = fittedSize(maxWidth: visibleFrame.width, maxHeight: visibleFrame.height * fittedHeightUsage)
        let minimumUsableHeight = minimumUsableWidth * letterAspectRatio

        guard fittedSize.width < minimumUsableWidth,
              visibleFrame.width >= minimumUsableWidth,
              visibleFrame.height >= minimumUsableHeight * minimumUsableHeightTolerance else {
            return fittedSize
        }

        return CGSize(width: minimumUsableWidth, height: minimumUsableHeight)
    }

    private static var preferredVisibleFrame: CGRect? {
        if let mainScreen = NSScreen.main {
            return mainScreen.visibleFrame
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen.visibleFrame
        }

        return NSScreen.screens.first?.visibleFrame
    }

    static func sidebarResizedFrame(
        windowFrame: CGRect,
        screenVisibleFrame: CGRect,
        sidebarDelta: CGFloat
    ) -> CGRect {
        let targetWidth = max(windowFrame.width + sidebarDelta, minimumUsableWidth)
        let clampedWidth = min(targetWidth, screenVisibleFrame.width)

        var newOriginX = windowFrame.origin.x

        if newOriginX + clampedWidth > screenVisibleFrame.maxX {
            newOriginX = screenVisibleFrame.maxX - clampedWidth
        }

        newOriginX = max(newOriginX, screenVisibleFrame.origin.x)

        return CGRect(
            x: newOriginX,
            y: windowFrame.origin.y,
            width: clampedWidth,
            height: windowFrame.height
        )
    }

    private static func fittedSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let scale = min(1, maxWidth / baseWidth, maxHeight / baseHeight)
        return CGSize(
            width: max(baseWidth * scale, 1),
            height: max(baseHeight * scale, 1)
        )
    }
}