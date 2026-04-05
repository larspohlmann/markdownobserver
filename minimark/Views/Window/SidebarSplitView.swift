import AppKit
import SwiftUI

/// Bridges to AppKit to set the NSSplitView divider position and holding priorities.
///
/// Uses a two-tier holding priority strategy:
/// - Normal: priority 999 — sidebar strongly resists proportional resizing during window resize
/// - During divider drag: priority 750 — allows user-initiated resize
///
/// This avoids exposing any drag state to SwiftUI, so no view re-renders occur during drag.
/// The final width is reported on mouse-up via `onDividerDragged`.
struct SidebarDividerPositionSetter: NSViewRepresentable {
    let targetWidth: CGFloat
    let placement: ReaderMultiFileDisplayMode.SidebarPlacement
    let onDividerDragged: (CGFloat) -> Void

    func makeNSView(context: Context) -> SidebarPositionHelperView {
        let view = SidebarPositionHelperView()
        view.isHidden = true
        view.targetWidth = targetWidth
        view.placement = placement
        view.onDividerDragged = onDividerDragged
        return view
    }

    func updateNSView(_ nsView: SidebarPositionHelperView, context: Context) {
        nsView.onDividerDragged = onDividerDragged
        nsView.updateIfNeeded(targetWidth: targetWidth, placement: placement)
    }
}

final class SidebarPositionHelperView: NSView {
    /// High priority used normally — sidebar strongly resists window-resize redistribution.
    private static let lockedHoldingPriority = NSLayoutConstraint.Priority(999)
    /// Lower priority during divider drag — allows user-initiated resize.
    private static let draggingHoldingPriority: NSLayoutConstraint.Priority = .defaultHigh
    private static let widthEpsilon: CGFloat = 1
    private static let dividerHitZone: CGFloat = 6

    var targetWidth: CGFloat = 0
    var placement: ReaderMultiFileDisplayMode.SidebarPlacement = .left
    var onDividerDragged: ((CGFloat) -> Void)?
    private var lastAppliedWidth: CGFloat = 0
    private var lastAppliedPlacement: ReaderMultiFileDisplayMode.SidebarPlacement?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isDraggingDivider = false

    private var sidebarSubviewIndex: Int { placement == .left ? 0 : 1 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMouseMonitors()
        guard window != nil else { return }
        installMouseMonitors()
        applyPosition()
    }

    deinit {
        removeMouseMonitors()
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

    // MARK: - Mouse monitoring

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

        let dividerX = placement == .left ? sidebarFrame.maxX : sidebarFrame.minX
        if abs(locationInSplitView.x - dividerX) <= Self.dividerHitZone + splitView.dividerThickness {
            isDraggingDivider = true
            // Lower holding priority so the sidebar can be resized by the user
            splitView.setHoldingPriority(Self.draggingHoldingPriority, forSubviewAt: sidebarSubviewIndex)
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDraggingDivider else { return }
        isDraggingDivider = false

        guard let splitView = ancestorSplitView(), splitView.subviews.count > 1 else { return }

        let finalWidth = splitView.subviews[sidebarSubviewIndex].frame.width

        // Re-engage high holding priority so the sidebar resists window-resize redistribution
        splitView.setHoldingPriority(Self.lockedHoldingPriority, forSubviewAt: sidebarSubviewIndex)

        if finalWidth > 0 {
            targetWidth = finalWidth
            lastAppliedWidth = finalWidth
            onDividerDragged?(finalWidth)
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
        splitView.setHoldingPriority(Self.lockedHoldingPriority, forSubviewAt: sidebarSubviewIndex)
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
