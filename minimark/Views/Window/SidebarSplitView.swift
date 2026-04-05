import AppKit
import SwiftUI

struct SidebarSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebarWidth: CGFloat
    let sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    let onSidebarWidthChanged: (CGFloat) -> Void
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebarWidth = sidebarWidth
        self.sidebarPlacement = sidebarPlacement
        self.onSidebarWidthChanged = onSidebarWidthChanged
        self.sidebar = sidebar()
        self.detail = detail()
    }

    func makeNSViewController(context: Context) -> SidebarSplitViewController {
        SidebarSplitViewController(
            sidebar: AnyView(sidebar),
            detail: AnyView(detail),
            sidebarWidth: sidebarWidth,
            sidebarPlacement: sidebarPlacement,
            onSidebarWidthChanged: onSidebarWidthChanged
        )
    }

    func updateNSViewController(_ controller: SidebarSplitViewController, context: Context) {
        controller.update(
            sidebar: AnyView(sidebar),
            detail: AnyView(detail),
            sidebarWidth: sidebarWidth,
            sidebarPlacement: sidebarPlacement,
            onSidebarWidthChanged: onSidebarWidthChanged
        )
    }
}

// MARK: - SidebarSplitViewController

@MainActor
final class SidebarSplitViewController: NSSplitViewController {
    private static let sidebarMinWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth
    private static let sidebarHoldingPriority: NSLayoutConstraint.Priority = .defaultHigh
    private static let dividerHitZone: CGFloat = 6

    private let sidebarHostingController: NSHostingController<AnyView>
    private let detailHostingController: NSHostingController<AnyView>
    private var sidebarItem: NSSplitViewItem
    private var detailItem: NSSplitViewItem

    private var currentSidebarWidth: CGFloat
    private var currentPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    private var onSidebarWidthChanged: (CGFloat) -> Void

    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isDraggingDivider = false

    init(
        sidebar: AnyView,
        detail: AnyView,
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void
    ) {
        sidebarHostingController = NSHostingController(rootView: sidebar)
        sidebarHostingController.sizingOptions = []
        detailHostingController = NSHostingController(rootView: detail)
        detailHostingController.sizingOptions = []
        sidebarItem = NSSplitViewItem(viewController: sidebarHostingController)
        detailItem = NSSplitViewItem(viewController: detailHostingController)
        self.currentSidebarWidth = sidebarWidth
        self.currentPlacement = sidebarPlacement
        self.onSidebarWidthChanged = onSidebarWidthChanged

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarItem.minimumThickness = Self.sidebarMinWidth
        sidebarItem.holdingPriority = Self.sidebarHoldingPriority
        detailItem.minimumThickness = ReaderSidebarWorkspaceMetrics.detailMinimumWidth
        detailItem.holdingPriority = .defaultLow

        if sidebarPlacement == .left {
            addSplitViewItem(sidebarItem)
            addSplitViewItem(detailItem)
        } else {
            addSplitViewItem(detailItem)
            addSplitViewItem(sidebarItem)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applySidebarWidth(currentSidebarWidth)
        installMouseMonitors()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeMouseMonitors()
    }

    func update(
        sidebar: AnyView,
        detail: AnyView,
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void
    ) {
        sidebarHostingController.rootView = sidebar
        detailHostingController.rootView = detail
        self.onSidebarWidthChanged = onSidebarWidthChanged

        if sidebarPlacement != currentPlacement {
            currentPlacement = sidebarPlacement
            reorderItems(for: sidebarPlacement)
        }

        if !isDraggingDivider, abs(sidebarWidth - currentSidebarWidth) > 1 {
            currentSidebarWidth = sidebarWidth
            applySidebarWidth(sidebarWidth)
        }
    }

    // MARK: - Divider width management

    private func applySidebarWidth(_ width: CGFloat) {
        guard view.window != nil,
              splitView.arrangedSubviews.count > 1 else { return }

        let position: CGFloat
        if currentPlacement == .left {
            position = width
        } else {
            position = splitView.bounds.width - width - splitView.dividerThickness
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        splitView.setPosition(position, ofDividerAt: 0)
        CATransaction.commit()
    }

    private func reorderItems(for placement: ReaderMultiFileDisplayMode.SidebarPlacement) {
        removeSplitViewItem(sidebarItem)
        removeSplitViewItem(detailItem)

        if placement == .left {
            addSplitViewItem(sidebarItem)
            addSplitViewItem(detailItem)
        } else {
            addSplitViewItem(detailItem)
            addSplitViewItem(sidebarItem)
        }

        applySidebarWidth(currentSidebarWidth)
    }

    // MARK: - Mouse monitoring for divider drag

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
        guard splitView.arrangedSubviews.count > 1,
              event.window === view.window else { return }

        let sidebarIndex = currentPlacement == .left ? 0 : 1
        let sidebarFrame = splitView.arrangedSubviews[sidebarIndex].frame
        let location = splitView.convert(event.locationInWindow, from: nil)

        let dividerX = currentPlacement == .left ? sidebarFrame.maxX : sidebarFrame.minX
        if abs(location.x - dividerX) <= Self.dividerHitZone + splitView.dividerThickness {
            isDraggingDivider = true
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDraggingDivider else { return }
        isDraggingDivider = false

        let sidebarIndex = currentPlacement == .left ? 0 : 1
        guard splitView.arrangedSubviews.count > 1 else { return }
        let finalWidth = splitView.arrangedSubviews[sidebarIndex].frame.width
        if finalWidth > 0, abs(finalWidth - currentSidebarWidth) > 1 {
            currentSidebarWidth = finalWidth
            onSidebarWidthChanged(finalWidth)
        }
    }
}
