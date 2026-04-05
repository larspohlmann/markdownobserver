import AppKit
import SwiftUI

/// Bridges to AppKit to set NSSplitView holding priorities and divider position,
/// and reports the sidebar width after the user finishes dragging the divider.
/// Attaches as a hidden background on the sidebar column inside an HSplitView.
struct SidebarWidthBridge: NSViewRepresentable {
    let targetWidth: CGFloat
    let placement: ReaderMultiFileDisplayMode.SidebarPlacement
    let onSidebarWidthChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> SidebarWidthBridgeView {
        let view = SidebarWidthBridgeView()
        view.isHidden = true
        view.targetWidth = targetWidth
        view.placement = placement
        view.onSidebarWidthChanged = onSidebarWidthChanged
        return view
    }

    func updateNSView(_ nsView: SidebarWidthBridgeView, context: Context) {
        nsView.onSidebarWidthChanged = onSidebarWidthChanged
        nsView.updateIfNeeded(targetWidth: targetWidth, placement: placement)
    }
}

// MARK: - SidebarWidthBridgeView

final class SidebarWidthBridgeView: NSView {
    private static let sidebarHoldingPriority: NSLayoutConstraint.Priority = .defaultHigh
    private static let widthEpsilon: CGFloat = 1

    var targetWidth: CGFloat = 0
    var placement: ReaderMultiFileDisplayMode.SidebarPlacement = .left
    var onSidebarWidthChanged: ((CGFloat) -> Void)?
    private var lastAppliedWidth: CGFloat = 0
    private var lastAppliedPlacement: ReaderMultiFileDisplayMode.SidebarPlacement?
    private var mouseUpMonitor: Any?
    private var isDraggingDivider = false
    private var resizeObserver: NSObjectProtocol?

    private var sidebarSubviewIndex: Int { placement == .left ? 0 : 1 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitors()
        guard window != nil else { return }
        installMonitors()
        applyPosition()
    }

    deinit {
        removeMonitors()
    }

    func updateIfNeeded(targetWidth newWidth: CGFloat, placement newPlacement: ReaderMultiFileDisplayMode.SidebarPlacement) {
        let widthChanged = abs(targetWidth - newWidth) > Self.widthEpsilon
        let placementChanged = placement != newPlacement
        if widthChanged { targetWidth = newWidth }
        if placementChanged { placement = newPlacement }
        if widthChanged || placementChanged {
            lastAppliedWidth = 0
            applyPosition()
        }
    }

    // MARK: - Monitoring

    private func installMonitors() {
        guard let splitView = ancestorSplitView() else { return }

        // Observe NSSplitView resize to detect user-initiated divider drags.
        // This fires for both user drags and programmatic resizes; we use
        // isDraggingDivider + mouse-up to distinguish and report only user drags.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isDraggingDivider else { return }
            // A subview resize happened without us tracking a drag — check if the
            // mouse is currently down (the user is dragging the divider right now).
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.isDraggingDivider = true
            }
        }

        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }
    }

    private func removeMonitors() {
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        resizeObserver = nil
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        mouseUpMonitor = nil
        isDraggingDivider = false
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDraggingDivider else { return }
        isDraggingDivider = false

        if let splitView = ancestorSplitView(), splitView.subviews.count > 1 {
            let finalWidth = splitView.subviews[sidebarSubviewIndex].frame.width
            if finalWidth > 0 {
                targetWidth = finalWidth
                lastAppliedWidth = finalWidth
                onSidebarWidthChanged?(finalWidth)
            }
        }
    }

    // MARK: - Position application

    private func applyPosition() {
        guard let splitView = ancestorSplitView(),
              splitView.arrangedSubviews.count > 1,
              splitView.delegate as? NSSplitViewController == nil else {
            return
        }
        guard abs(lastAppliedWidth - targetWidth) > Self.widthEpsilon
                || lastAppliedPlacement != placement else {
            return
        }
        lastAppliedWidth = targetWidth
        lastAppliedPlacement = placement

        let detailIndex = placement == .left ? 1 : 0
        splitView.setHoldingPriority(Self.sidebarHoldingPriority, forSubviewAt: sidebarSubviewIndex)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: detailIndex)

        let position: CGFloat
        if placement == .left {
            position = targetWidth
        } else {
            position = splitView.bounds.width - targetWidth - splitView.dividerThickness
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        splitView.setPosition(position, ofDividerAt: 0)
        CATransaction.commit()
    }

    private func ancestorSplitView() -> NSSplitView? {
        var current = superview
        while let view = current {
            if let split = view as? NSSplitView { return split }
            current = view.superview
        }
        return nil
    }
}
