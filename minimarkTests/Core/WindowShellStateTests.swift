//
//  WindowShellStateTests.swift
//  minimarkTests
//

import AppKit
import Testing
@testable import minimark

@Suite(.serialized)
struct WindowShellStateTests {

    @Test @MainActor
    func handleWindowAccessorUpdateSkipsSameWindow() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        // First call -- should set hostWindow
        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)

        // Record title after first call
        let titleAfterFirst = coordinator.effectiveWindowTitle

        // Second call with same window -- should be a no-op
        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)
        #expect(coordinator.effectiveWindowTitle == titleAfterFirst)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateProcessesNewWindow() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window1 = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let window2 = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        coordinator.handleWindowAccessorUpdate(window1)
        #expect(coordinator.hostWindow === window1)

        coordinator.handleWindowAccessorUpdate(window2)
        #expect(coordinator.hostWindow === window2)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateNilUnregistersAndProcesses() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)

        coordinator.handleWindowAccessorUpdate(nil)
        #expect(coordinator.hostWindow == nil)
    }

    @Test @MainActor
    func registerWindowIfNeededIsIdempotent() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        coordinator.handleWindowAccessorUpdate(window)

        // Calling registerWindowIfNeeded multiple times should not fail or cause issues.
        // We verify by checking the window is still properly registered after multiple calls.
        coordinator.registerWindowIfNeeded()
        coordinator.registerWindowIfNeeded()
        coordinator.registerWindowIfNeeded()

        // Window should still be registered and functional
        #expect(coordinator.hostWindow === window)
    }

    @Test @MainActor
    func refreshWindowShellStateAppliesTitle() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        coordinator.handleWindowAccessorUpdate(window)

        // refreshWindowShellState should apply the title (behavioral parity with old nested version)
        coordinator.refreshWindowShellState()

        // The effective title should be the app name since no document is selected
        #expect(coordinator.effectiveWindowTitle == ReaderWindowTitleFormatter.appName)
        #expect(window.title == ReaderWindowTitleFormatter.appName)
    }

    @Test @MainActor
    func registrationIdentityClearedOnNilWindow() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = ReaderWindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        // Register with a window
        coordinator.handleWindowAccessorUpdate(window)

        // Unregister by setting nil
        coordinator.handleWindowAccessorUpdate(nil)

        // Re-registering the same window should work (identity was cleared)
        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)
    }
}
