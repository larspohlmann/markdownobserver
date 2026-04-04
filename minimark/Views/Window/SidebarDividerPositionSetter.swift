import AppKit
import SwiftUI

/// Bridges to AppKit to set the NSSplitView divider position and holding priorities.
/// HSplitView ignores `idealWidth` for restored widths, so this applies the correct
/// position programmatically on first appearance and whenever width or placement changes.
///
/// Also monitors mouse events to detect divider drags: when the user clicks near the
/// divider, `onDividerDragActive` is called with `true` to lift the `maxWidth` constraint,
/// allowing the sidebar to resize. On mouse up, it's called with `false` and the new
/// sidebar width is reported via `onDividerDragged`.
struct SidebarDividerPositionSetter: NSViewRepresentable {
    let targetWidth: CGFloat
    let placement: ReaderMultiFileDisplayMode.SidebarPlacement
    let onDividerDragged: (CGFloat) -> Void
    let onDividerDragActive: (Bool) -> Void

    func makeNSView(context: Context) -> SidebarPositionHelperView {
        let view = SidebarPositionHelperView()
        view.isHidden = true
        view.targetWidth = targetWidth
        view.placement = placement
        view.onDividerDragged = onDividerDragged
        view.onDividerDragActive = onDividerDragActive
        return view
    }

    func updateNSView(_ nsView: SidebarPositionHelperView, context: Context) {
        nsView.onDividerDragged = onDividerDragged
        nsView.onDividerDragActive = onDividerDragActive
        nsView.updateIfNeeded(targetWidth: targetWidth, placement: placement)
    }
}

final class SidebarPositionHelperView: NSView {
    /// High holding priority so the sidebar strongly resists proportional
    /// resizing when the window expands or shrinks.
    private static let sidebarHoldingPriority: NSLayoutConstraint.Priority = .defaultHigh
    private static let widthEpsilon: CGFloat = 1
    private static let dividerHitZone: CGFloat = 6

    var targetWidth: CGFloat = 0
    var placement: ReaderMultiFileDisplayMode.SidebarPlacement = .left
    var onDividerDragged: ((CGFloat) -> Void)?
    var onDividerDragActive: ((Bool) -> Void)?
    private var lastAppliedWidth: CGFloat = 0
    private var lastAppliedPlacement: ReaderMultiFileDisplayMode.SidebarPlacement?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isDraggingDivider = false

    private var sidebarSubviewIndex: Int { placement == .left ? 0 : 1 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMouseMonitors()
        guard window != nil else {
            resetDividerDragIfNeeded()
            return
        }
        installMouseMonitors()
        applyPosition()
    }

    deinit {
        resetDividerDragIfNeeded()
        removeMouseMonitors()
    }

    private func resetDividerDragIfNeeded() {
        guard isDraggingDivider else { return }
        isDraggingDivider = false
        onDividerDragActive?(false)
    }

    private func installMouseMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event)
            return event
        }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }
    }

    private func removeMouseMonitors() {
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        mouseDownMonitor = nil
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        mouseUpMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard let splitView = ancestorSplitView(),
              splitView.subviews.count > 1,
              event.window === self.window else { return }

        let sidebarFrame = splitView.subviews[sidebarSubviewIndex].frame
        let locationInSplitView = splitView.convert(event.locationInWindow, from: nil)

        // Check if click is near the divider edge
        let dividerX = placement == .left ? sidebarFrame.maxX : sidebarFrame.minX
        if abs(locationInSplitView.x - dividerX) <= Self.dividerHitZone + splitView.dividerThickness {
            isDraggingDivider = true
            onDividerDragActive?(true)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDraggingDivider else { return }
        isDraggingDivider = false

        // Read the final sidebar width from NSSplitView
        if let splitView = ancestorSplitView(), splitView.subviews.count > 1 {
            let finalWidth = splitView.subviews[sidebarSubviewIndex].frame.width
            if finalWidth > 0 {
                targetWidth = finalWidth
                lastAppliedWidth = finalWidth
                onDividerDragged?(finalWidth)
            }
        }

        // Re-engage the maxWidth constraint
        onDividerDragActive?(false)
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
