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
    private func makeCoordinator() throws -> (ReaderWindowCoordinator, ReaderSidebarControllerTestHarness) {
        let harness = try ReaderSidebarControllerTestHarness()
        let coordinator = ReaderWindowCoordinator(
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

        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)

        let titleAfterFirst = coordinator.effectiveWindowTitle

        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)
        #expect(coordinator.effectiveWindowTitle == titleAfterFirst)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateProcessesNewWindow() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window1 = makeWindow()
        let window2 = makeWindow()

        coordinator.handleWindowAccessorUpdate(window1)
        #expect(coordinator.hostWindow === window1)

        coordinator.handleWindowAccessorUpdate(window2)
        #expect(coordinator.hostWindow === window2)
    }

    @Test @MainActor
    func handleWindowAccessorUpdateNilUnregistersAndProcesses() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()

        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)

        coordinator.handleWindowAccessorUpdate(nil)
        #expect(coordinator.hostWindow == nil)
    }

    @Test @MainActor
    func registerWindowIfNeededIsIdempotent() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()
        coordinator.handleWindowAccessorUpdate(window)

        coordinator.registerWindowIfNeeded()
        coordinator.registerWindowIfNeeded()
        coordinator.registerWindowIfNeeded()

        #expect(coordinator.hostWindow === window)
    }

    @Test @MainActor
    func refreshWindowShellStateAppliesTitle() throws {
        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()
        coordinator.handleWindowAccessorUpdate(window)

        coordinator.refreshWindowShellState()

        #expect(coordinator.effectiveWindowTitle == ReaderWindowTitleFormatter.appName)
        #expect(window.title == ReaderWindowTitleFormatter.appName)
    }

    @Test @MainActor
    func registrationIdentityClearedOnNilWindow() throws {
        ReaderWindowRegistry.shared.resetForTesting()
        defer { ReaderWindowRegistry.shared.resetForTesting() }

        let (coordinator, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        let window = makeWindow()

        coordinator.handleWindowAccessorUpdate(window)
        coordinator.handleWindowAccessorUpdate(nil)

        // Re-registering the same window should work (identity was cleared)
        coordinator.handleWindowAccessorUpdate(window)
        #expect(coordinator.hostWindow === window)
    }
}
