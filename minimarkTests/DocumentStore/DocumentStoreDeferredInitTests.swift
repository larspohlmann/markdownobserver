import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct DocumentStoreDeferredInitTests {
    @Test @MainActor func settingsSubscriptionNotActiveBeforeFileOpen() async throws {
        let fixture = try DocumentStoreTestFixture(autoRefreshOnExternalChange: false)
        defer { fixture.cleanup() }

        // Change the diff baseline lookback BEFORE opening a file.
        // The store should NOT have an active subscription yet,
        // so the diffBaselineTracker's currentMinimumAge should remain unchanged.
        let originalAge = fixture.store.diffBaselineTracker.currentMinimumAge
        fixture.settings.updateDiffBaselineLookback(.fiveMinutes)

        // Drain the main queue — the Combine sink uses .receive(on: DispatchQueue.main).
        await Task.yield()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        #expect(fixture.store.diffBaselineTracker.currentMinimumAge == originalAge)
    }

    @Test @MainActor func settingsSubscriptionActivatesAfterFileOpen() async throws {
        let fixture = try DocumentStoreTestFixture(
            autoRefreshOnExternalChange: false,
            diffBaselineLookback: .twoMinutes
        )
        defer { fixture.cleanup() }

        // Open a file — this should activate the subscription.
        fixture.store.opener.open(at: fixture.primaryFileURL)

        // Now change the lookback — the store should observe it.
        fixture.settings.updateDiffBaselineLookback(.fiveMinutes)

        // Drain the main queue — the Combine sink uses .receive(on: DispatchQueue.main).
        // We need to yield to let GCD process the dispatched block, then pump the
        // run loop to process any remaining scheduled work.
        let delivered = await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.store.diffBaselineTracker.currentMinimumAge == DiffBaselineLookback.fiveMinutes.timeInterval
        }

        #expect(delivered, "Combine subscription should have delivered the updated lookback value")
        let expectedAge = DiffBaselineLookback.fiveMinutes.timeInterval
        #expect(fixture.store.diffBaselineTracker.currentMinimumAge == expectedAge)
    }
}
