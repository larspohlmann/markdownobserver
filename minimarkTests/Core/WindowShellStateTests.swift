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
}
