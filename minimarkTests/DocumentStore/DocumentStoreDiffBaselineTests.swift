//
//  DocumentStoreDiffBaselineTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct DocumentStoreDiffBaselineTests {
    @Test @MainActor func externalChangeDiffsAgainstAgedBaselineNotImmediatePrevious() throws {
        let fixture = try DocumentStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenMinutes
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.differ.computeChangedRegionsCalls = []

        // First external change
        fixture.write(content: "# Changed once", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        // Second external change
        fixture.write(content: "# Changed twice", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        // With a 10-minute lookback, nothing is old enough to be "aged".
        // Fallback is the oldest recorded baseline ("# Initial").
        // So the second diff should be against "# Initial", NOT "# Changed once".
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Initial")
        #expect(lastDiffCall?.newMarkdown == "# Changed twice")
    }

    @Test @MainActor func externalChangeWithShortLookbackFallsToOldestWhenNothingIsAged() throws {
        let fixture = try DocumentStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenSeconds
        )
        defer { fixture.cleanup() }

        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.differ.computeChangedRegionsCalls = []

        fixture.write(content: "# Changed once", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        fixture.write(content: "# Changed twice", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        // Even with 10s lookback, nothing is old enough (< 1ms between changes).
        // Fallback is still the oldest baseline ("# Initial").
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Initial")
        #expect(lastDiffCall?.newMarkdown == "# Changed twice")
    }

    @Test @MainActor func switchingFilesKeepsIndependentBaselineHistories() throws {
        let fixture = try DocumentStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenMinutes
        )
        defer { fixture.cleanup() }

        // Build up history for the primary file
        fixture.store.opener.open(at: fixture.primaryFileURL)
        fixture.write(content: "# Primary changed", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        fixture.differ.computeChangedRegionsCalls = []

        // Switch to the secondary file
        fixture.store.opener.open(at: fixture.secondaryFileURL)

        // Change the secondary file
        fixture.write(content: "# Second changed", to: fixture.secondaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        // The diff should be against "# Second" (the secondary file's own history),
        // NOT against anything from the primary file's history.
        // Per-file-URL keying keeps histories independent.
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Second")
    }

    @Test @MainActor func autoOpenedFileUsesInitialBaselineForSubsequentChanges() throws {
        let fixture = try DocumentStoreTestFixture(
            autoRefreshOnExternalChange: true,
            diffBaselineLookback: .tenMinutes
        )
        defer { fixture.cleanup() }

        // Simulate sidebar auto-open: file changed from "# Before" to "# After auto-open"
        fixture.write(content: "# After auto-open", to: fixture.primaryFileURL)
        fixture.store.opener.open(
            at: fixture.primaryFileURL,
            origin: .folderWatchAutoOpen,
            initialDiffBaselineMarkdown: "# Before"
        )

        // Clear settler (simulates expiry)
        fixture.store.folderWatch.settler.clearSettling()
        fixture.differ.computeChangedRegionsCalls = []

        // External change after settler expired
        fixture.write(content: "# Changed again", to: fixture.primaryFileURL)
        fixture.store.externalChangeHandler.handleObservedFileChange()

        // The diff should be against "# Before" (the initial baseline),
        // not "# After auto-open" (the content at auto-open time).
        let lastDiffCall = fixture.differ.computeChangedRegionsCalls.last
        #expect(lastDiffCall?.oldMarkdown == "# Before")
        #expect(lastDiffCall?.newMarkdown == "# Changed again")
    }
}
