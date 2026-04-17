import AppKit
import Foundation
import Observation

/// Owns the window's sidebar width and the metrics needed to animate the host
/// window's frame when sidebar visibility flips.
///
/// Two responsibilities packaged together because they share the
/// `lastAppliedDelta` state machine: a width change writes through to the
/// favorite workspace if one is active, and a visibility flip animates the
/// window frame using the most recently applied delta. Splitting them would
/// fragment that state.
@MainActor
@Observable
final class WindowSidebarMetricsController {
    var width: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    @ObservationIgnored private var lastAppliedDelta: CGFloat = 0

    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let favoriteWorkspaceControllerProvider: () -> FavoriteWorkspaceController?
    private let hostWindowProvider: () -> NSWindow?

    init(
        sidebarDocumentController: ReaderSidebarDocumentController,
        favoriteWorkspaceControllerProvider: @escaping () -> FavoriteWorkspaceController?,
        hostWindowProvider: @escaping () -> NSWindow?
    ) {
        self.sidebarDocumentController = sidebarDocumentController
        self.favoriteWorkspaceControllerProvider = favoriteWorkspaceControllerProvider
        self.hostWindowProvider = hostWindowProvider
    }

    func resetToIdealWidth() {
        width = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
    }

    func handleWidthChange(_ newWidth: CGFloat) {
        width = newWidth
        if favoriteWorkspaceControllerProvider()?.activeFavoriteWorkspaceState != nil,
           sidebarDocumentController.documents.count > 1 {
            favoriteWorkspaceControllerProvider()?.updateSidebarWidth(newWidth)
        }
    }

    func handleVisibilityChange(oldCount: Int, newCount: Int) {
        let isSidebarVisible = newCount > 1
        let wasVisible = oldCount > 1

        guard isSidebarVisible != wasVisible, let window = hostWindowProvider() else {
            return
        }

        if isSidebarVisible,
           let favoriteWidth = favoriteWorkspaceControllerProvider()?.activeFavoriteWorkspaceState?.sidebarWidth {
            width = favoriteWidth
        }

        let delta = isSidebarVisible
            ? width
            : -lastAppliedDelta

        guard let screenFrame = window.screen?.visibleFrame else {
            return
        }

        let oldWidth = window.frame.width
        let newFrame = WindowDefaults.sidebarResizedFrame(
            windowFrame: window.frame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: delta
        )

        window.setFrame(newFrame, display: true, animate: true)

        if isSidebarVisible {
            lastAppliedDelta = newFrame.width - oldWidth
        } else {
            lastAppliedDelta = 0
            width = ReaderSidebarWorkspaceMetrics.sidebarIdealWidth
        }
    }
}
