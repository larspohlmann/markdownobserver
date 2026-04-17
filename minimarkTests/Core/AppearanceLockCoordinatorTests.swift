import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct AppearanceLockCoordinatorTests {

    @MainActor
    private func makeCoordinator() throws -> (
        AppearanceLockCoordinator,
        WindowAppearanceController,
        ReaderSidebarControllerTestHarness
    ) {
        let harness = try ReaderSidebarControllerTestHarness()
        let appearanceController = WindowAppearanceController(settingsStore: harness.settingsStore)
        let coordinator = AppearanceLockCoordinator(
            appearanceControllerProvider: { appearanceController },
            sidebarDocumentController: harness.controller,
            favoriteWorkspaceControllerProvider: { nil }
        )
        return (coordinator, appearanceController, harness)
    }

    @Test @MainActor
    func toggleLockSwitchesAppearanceControllerLockState() throws {
        let (coordinator, appearanceController, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        #expect(appearanceController.isLocked == false)

        coordinator.toggleLock()
        #expect(appearanceController.isLocked == true)

        coordinator.toggleLock()
        #expect(appearanceController.isLocked == false)
    }

    @Test @MainActor
    func renderSelectedDocumentIfNeededIsNoOpWithoutSelection() throws {
        let (coordinator, _, harness) = try makeCoordinator()
        defer { harness.cleanup() }

        // No documents in the harness controller — should be a safe no-op.
        coordinator.renderSelectedDocumentIfNeeded()
    }
}
