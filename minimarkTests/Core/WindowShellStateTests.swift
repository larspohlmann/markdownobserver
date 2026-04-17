//
//  WindowShellStateTests.swift
//  minimarkTests
//

import AppKit
import Testing
@testable import minimark

@Suite(.serialized)
struct WindowShellStateTests {

    @MainActor
    private func makeCoordinator() throws -> (WindowCoordinator, SidebarControllerTestHarness) {
        WindowRegistry.shared.resetForTesting()
        let harness = try SidebarControllerTestHarness()
        let coordinator = WindowCoordinator(
            settingsStore: harness.settingsStore,
            sidebarDocumentController: harness.controller
        )
        return (coordinator, harness)
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
    func handleWindowAccessorUpdateSkipsSameWindow() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()

        coordinator.events.handleWindowAccessorUpdate(window)
        #expect(coordinator.shell.hostWindow === window)

        let titleAfterFirst = coordinator.shell.effectiveWindowTitle

        coordinator.events.handleWindowAccessorUpdate(window)
        #expect(coordinator.shell.hostWindow === window)
        #expect(coordinator.shell.effectiveWindowTitle == titleAfterFirst)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateProcessesNewWindow() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window1 = makeWindow()
        let window2 = makeWindow()

        coordinator.events.handleWindowAccessorUpdate(window1)
        #expect(coordinator.shell.hostWindow === window1)

        coordinator.events.handleWindowAccessorUpdate(window2)
        #expect(coordinator.shell.hostWindow === window2)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateNilUnregistersAndProcesses() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()

        coordinator.events.handleWindowAccessorUpdate(window)
        #expect(coordinator.shell.hostWindow === window)

        coordinator.events.handleWindowAccessorUpdate(nil)
        #expect(coordinator.shell.hostWindow == nil)
    }

    @Test @MainActor
    func registerWindowIfNeededIsIdempotent() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()
        coordinator.events.handleWindowAccessorUpdate(window)

        coordinator.shell.registerIfNeeded()
        coordinator.shell.registerIfNeeded()
        coordinator.shell.registerIfNeeded()

        #expect(coordinator.shell.hostWindow === window)
    }

    @Test @MainActor
    func refreshWindowShellStateAppliesTitle() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()
        coordinator.events.handleWindowAccessorUpdate(window)

        coordinator.refreshWindowShellState()

        #expect(coordinator.shell.effectiveWindowTitle == WindowTitleFormatter.appName)
        #expect(window.title == WindowTitleFormatter.appName)
    }

    @Test @MainActor
    func registrationIdentityClearedOnNilWindow() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()

        coordinator.events.handleWindowAccessorUpdate(window)
        coordinator.events.handleWindowAccessorUpdate(nil)

        // Re-registering the same window should work (identity was cleared)
        coordinator.events.handleWindowAccessorUpdate(window)
        #expect(coordinator.shell.hostWindow === window)
    }
}
