//
//  ReaderStoreDiffBaselineTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreDiffBaselineTests {
    @Test @MainActor func externalChangeDiffsAgainstAgedBaselineNotImmediatePrevious() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenMinutes
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.differ.computeChangedRegionsCalls = []

        // First external change
        fixture.write(content: "# Changed once", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        // Second external change
        fixture.write(content: "# Changed twice", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        // With a 10-minute lookback, nothing is old enough to be "aged".
        // Fallback is the oldest recorded baseline ("# Initial").
        // So the second diff should be against "# Initial", NOT "# Changed once".
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Initial")
        #expect(lastDiffCall?.newMarkdown == "# Changed twice")
    }

    @Test @MainActor func externalChangeWithShortLookbackFallsToOldestWhenNothingIsAged() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenSeconds
        )
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.differ.computeChangedRegionsCalls = []

        fixture.write(content: "# Changed once", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        fixture.write(content: "# Changed twice", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        // Even with 10s lookback, nothing is old enough (< 1ms between changes).
        // Fallback is still the oldest baseline ("# Initial").
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Initial")
        #expect(lastDiffCall?.newMarkdown == "# Changed twice")
    }

    @Test @MainActor func switchingFilesKeepsIndependentBaselineHistories() throws {
        let fixture = try ReaderStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenMinutes
        )
        defer { fixture.cleanup() }

        // Build up history for the primary file
        fixture.store.openFile(at: fixture.primaryFileURL)
        fixture.write(content: "# Primary changed", to: fixture.primaryFileURL)
        fixture.store.handleObservedFileChange()

        fixture.differ.computeChangedRegionsCalls = []

        // Switch to the secondary file
        fixture.store.openFile(at: fixture.secondaryFileURL)

        // Change the secondary file
        fixture.write(content: "# Second changed", to: fixture.secondaryFileURL)
        fixture.store.handleObservedFileChange()

        // The diff should be against "# Second" (the secondary file's own history),
        // NOT against anything from the primary file's history.
        // Per-file-URL keying keeps histories independent.
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Second")
    }
}
