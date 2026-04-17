import AppKit
import Foundation
import Observation

/// Window-level controller that owns the host-window reference, the effective
/// window title, the window registry identity, and the dock-tile lifecycle.
///
/// Intentionally narrow: knows *how* to register a window, resolve its title,
/// and mirror the dock-tile row states. Does not know about folder-watch flow,
/// UI-test launch configuration, or the folder-watch open queue — those stay
/// with `ReaderWindowCoordinator` as composite concerns.
@MainActor
@Observable
final class WindowShellController {
    private let sidebarDocumentController: ReaderSidebarDocumentController
    private let folderWatchSessionProvider: () -> FolderWatchSession?

    var hostWindow: NSWindow?
    var effectiveWindowTitle: String = WindowTitleFormatter.appName
    let dockTileWindowToken = UUID()

    @ObservationIgnored private var registeredIdentity: RegisteredWindowIdentity?

    private struct RegisteredWindowIdentity: Equatable {
        let windowID: ObjectIdentifier
        let folderWatchSession: FolderWatchSession?

        init?(window: NSWindow?, folderWatchSession: FolderWatchSession?) {
            guard let window else { return nil }
            self.windowID = ObjectIdentifier(window)
            self.folderWatchSession = folderWatchSession
        }
    }

    init(
        sidebarDocumentController: ReaderSidebarDocumentController,
        folderWatchSessionProvider: @escaping () -> FolderWatchSession?
    ) {
        self.sidebarDocumentController = sidebarDocumentController
        self.folderWatchSessionProvider = folderWatchSessionProvider
    }

    /// Swap the host window reference. Unregisters the previous window if any.
    /// Returns `true` when the window reference actually changed — the caller
    /// is expected to follow up with `refreshRegistrationAndTitle()` (or a
    /// broader composite refresh) to re-register the new window.
    @discardableResult
    func updateHostWindow(_ window: NSWindow?) -> Bool {
        guard hostWindow !== window else { return false }
        if let existingWindow = hostWindow {
            WindowRegistry.shared.unregisterWindow(existingWindow)
            registeredIdentity = nil
        }
        hostWindow = window
        return true
    }

    func applyTitlePresentation() {
        let resolvedTitle = WindowTitleFormatter.resolveWindowTitle(
            documentTitle: sidebarDocumentController.selectedWindowTitle,
            activeFolderWatch: folderWatchSessionProvider(),
            hasUnacknowledgedExternalChange: sidebarDocumentController.selectedHasUnacknowledgedExternalChange
        )
        let mutation = WindowTitleFormatter.mutation(
            resolvedTitle: resolvedTitle,
            currentEffectiveTitle: effectiveWindowTitle,
            currentHostWindowTitle: hostWindow?.title
        )
        if mutation.shouldUpdateEffectiveTitle {
            effectiveWindowTitle = mutation.effectiveTitle
        }
        if mutation.shouldWriteHostWindowTitle {
            hostWindow?.title = mutation.effectiveTitle
        }
    }

    func registerIfNeeded() {
        let session = folderWatchSessionProvider()
        let currentIdentity = RegisteredWindowIdentity(
            window: hostWindow,
            folderWatchSession: session
        )
        guard currentIdentity != registeredIdentity else { return }
        registeredIdentity = currentIdentity
        WindowRegistry.shared.registerWindow(
            hostWindow,
            focusDocument: { [sidebarDocumentController] fileURL in
                sidebarDocumentController.focusDocument(at: fileURL)
            },
            watchedFolderURLProvider: { session?.folderURL }
        )
    }

    func refreshRegistrationAndTitle() {
        registerIfNeeded()
        applyTitlePresentation()
    }

    func configureDockTile() {
        DockTileController.shared.configureDockTileIfNeeded()
        let token = dockTileWindowToken
        sidebarDocumentController.onDockTileRowStatesChanged = { rowStates in
            DockTileController.shared.updateRowStates(for: token, rowStates: rowStates)
        }
        DockTileController.shared.updateRowStates(
            for: token,
            rowStates: sidebarDocumentController.rowStates
        )
    }

    func clearDockTile() {
        sidebarDocumentController.onDockTileRowStatesChanged = nil
        DockTileController.shared.removeRowStates(for: dockTileWindowToken)
    }
}
