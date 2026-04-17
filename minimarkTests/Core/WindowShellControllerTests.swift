import AppKit
import Testing
@testable import minimark

@Suite(.serialized)
struct WindowShellControllerTests {

    @MainActor
    private func makeShell(
        folderWatchSession: FolderWatchSession? = nil
    ) throws -> (WindowShellController, ReaderSidebarControllerTestHarness) {
        WindowRegistry.shared.resetForTesting()
        let harness = try ReaderSidebarControllerTestHarness()
        let shell = WindowShellController(
            sidebarDocumentController: harness.controller,
            folderWatchSessionProvider: { folderWatchSession }
        )
        return (shell, harness)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    @Test @MainActor
    func updateHostWindowReturnsFalseForSameWindow() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window = makeWindow()

        #expect(shell.updateHostWindow(window) == true)
        #expect(shell.updateHostWindow(window) == false)
        #expect(shell.hostWindow === window)
    }

    @Test @MainActor
    func updateHostWindowSwapsAndUnregistersPrevious() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window1 = makeWindow()
        let window2 = makeWindow()

        shell.updateHostWindow(window1)
        #expect(shell.hostWindow === window1)

        shell.updateHostWindow(window2)
        #expect(shell.hostWindow === window2)

        // Nil clears the reference.
        shell.updateHostWindow(nil)
        #expect(shell.hostWindow == nil)
    }

    @Test @MainActor
    func registerIfNeededIsIdempotent() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window = makeWindow()

        shell.updateHostWindow(window)
        shell.registerIfNeeded()
        shell.registerIfNeeded()
        shell.registerIfNeeded()

        #expect(shell.hostWindow === window)
    }

    @Test @MainActor
    func applyTitlePresentationWritesToHostWindow() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window = makeWindow()
        shell.updateHostWindow(window)

        shell.applyTitlePresentation()

        #expect(shell.effectiveWindowTitle == WindowTitleFormatter.appName)
        #expect(window.title == WindowTitleFormatter.appName)
    }

    @Test @MainActor
    func refreshRegistrationAndTitleComposesRegisterAndApply() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window = makeWindow()
        shell.updateHostWindow(window)

        shell.refreshRegistrationAndTitle()

        #expect(window.title == WindowTitleFormatter.appName)
    }

    @Test @MainActor
    func previousWindowIdentityClearedWhenHostNilled() throws {
        let (shell, harness) = try makeShell()
        defer { harness.cleanup() }
        let window = makeWindow()

        shell.updateHostWindow(window)
        shell.updateHostWindow(nil)

        // Re-registering the same window should work (identity was cleared).
        shell.updateHostWindow(window)
        #expect(shell.hostWindow === window)
    }
}
