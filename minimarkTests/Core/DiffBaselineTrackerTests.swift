//
//  DiffBaselineTrackerTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized) struct DiffBaselineTrackerTests {
    @Test func returnsInputMarkdownWhenHistoryIsEmpty() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let now = Date(timeIntervalSince1970: 1_000_000)

        let result = tracker.recordAndSelectBaseline(
            markdown: "# v0",
            for: fileURL,
            at: now
        )

        #expect(result.markdown == "# v0")
    }

    @Test func returnsFallbackBaselineWhenNothingIsOldEnough() {
        let tracker = DiffBaselineTracker(minimumAge: 60)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)

        now.addTimeInterval(5)
        let result = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        #expect(result.markdown == "# v0")
    }

    @Test func returnsMostRecentAgedBaseline() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)

        now.addTimeInterval(5)
        _ = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        now.addTimeInterval(8)
        let result = tracker.recordAndSelectBaseline(markdown: "# v2", for: fileURL, at: now)

        #expect(result.markdown == "# v0")
    }

    @Test func advancesToNewerAgedBaselineAsTimeProgresses() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)

        now.addTimeInterval(5)
        _ = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        now.addTimeInterval(10)
        let result = tracker.recordAndSelectBaseline(markdown: "# v2", for: fileURL, at: now)

        #expect(result.markdown == "# v1")
    }

    @Test func deduplicatesIdenticalConsecutiveRecords() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# same", for: fileURL, at: now)

        now.addTimeInterval(5)
        _ = tracker.recordAndSelectBaseline(markdown: "# same", for: fileURL, at: now)

        now.addTimeInterval(8)
        let result = tracker.recordAndSelectBaseline(markdown: "# new", for: fileURL, at: now)

        #expect(result.markdown == "# same")
    }

    @Test func capsHistoryAtMaximumDepth() {
        let tracker = DiffBaselineTracker(minimumAge: 0, maximumHistoryDepth: 3)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        for i in 0..<5 {
            now.addTimeInterval(1)
            _ = tracker.recordAndSelectBaseline(
                markdown: "# v\(i)",
                for: fileURL,
                at: now
            )
        }

        now.addTimeInterval(100)
        let result = tracker.recordAndSelectBaseline(
            markdown: "# v5",
            for: fileURL,
            at: now
        )

        #expect(result.markdown == "# v4")
    }

    @Test func updateMinimumAgeAffectsFutureSelections() {
        let tracker = DiffBaselineTracker(minimumAge: 60)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(15)
        _ = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        now.addTimeInterval(5)
        let before = tracker.recordAndSelectBaseline(markdown: "# v2", for: fileURL, at: now)
        #expect(before.markdown == "# v0")

        tracker.updateMinimumAge(10)

        now.addTimeInterval(1)
        let after = tracker.recordAndSelectBaseline(markdown: "# v3", for: fileURL, at: now)
        #expect(after.markdown == "# v0")
    }

    @Test func resetClearsAllHistory() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(5)
        _ = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        tracker.reset()

        now.addTimeInterval(1)
        let result = tracker.recordAndSelectBaseline(markdown: "# fresh", for: fileURL, at: now)

        #expect(result.markdown == "# fresh")
    }

    @Test func tracksMultipleFilesIndependently() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileA = URL(fileURLWithPath: "/tmp/a.md")
        let fileB = URL(fileURLWithPath: "/tmp/b.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# A-v0", for: fileA, at: now)
        _ = tracker.recordAndSelectBaseline(markdown: "# B-v0", for: fileB, at: now)

        now.addTimeInterval(15)
        let resultA = tracker.recordAndSelectBaseline(markdown: "# A-v1", for: fileA, at: now)
        let resultB = tracker.recordAndSelectBaseline(markdown: "# B-v1", for: fileB, at: now)

        #expect(resultA.markdown == "# A-v0")
        #expect(resultB.markdown == "# B-v0")
    }

    @Test func recordReturnsNewestRecordAndDeduplicates() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let now = Date(timeIntervalSince1970: 1_000_000)

        let first = tracker.record(markdown: "# a", for: fileURL, at: now)
        let again = tracker.record(markdown: "# a", for: fileURL, at: now.addingTimeInterval(1))

        #expect(first.markdown == "# a")
        #expect(again.id == first.id)
        #expect(tracker.snapshots(for: fileURL).count == 1)
    }

    @Test func snapshotsAreNewestFirst() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(5)
        tracker.record(markdown: "# v1", for: fileURL, at: now)

        let snapshots = tracker.snapshots(for: fileURL)
        #expect(snapshots.map(\.markdown) == ["# v1", "# v0"])
        #expect(tracker.snapshots(for: URL(fileURLWithPath: "/tmp/other.md")).isEmpty)
    }

    @Test func snapshotByIDFindsAndMisses() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        let now = Date(timeIntervalSince1970: 1_000_000)

        let recorded = tracker.record(markdown: "# v0", for: fileURL, at: now)

        #expect(tracker.snapshot(id: recorded.id, for: fileURL) == recorded)
        #expect(tracker.snapshot(id: UUID(), for: fileURL) == nil)
    }

    @Test func evictionDropsOldestIDs() {
        let tracker = DiffBaselineTracker(minimumAge: 0, maximumHistoryDepth: 2)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        let oldest = tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(1)
        tracker.record(markdown: "# v1", for: fileURL, at: now)
        now.addTimeInterval(1)
        tracker.record(markdown: "# v2", for: fileURL, at: now)

        #expect(tracker.snapshot(id: oldest.id, for: fileURL) == nil)
        #expect(tracker.snapshots(for: fileURL).map(\.markdown) == ["# v2", "# v1"])
    }

    @Test func recordAndSelectReturnsSnapshotWithStableID() {
        let tracker = DiffBaselineTracker(minimumAge: 10)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        let v0 = tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(15)
        let selected = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        #expect(selected.id == v0.id)
    }

    @Test func agedSelectionWithoutExclusionMayPickNewest() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = DiffBaselineSnapshot(markdown: "# old", capturedAt: now.addingTimeInterval(-300))
        let newer = DiffBaselineSnapshot(markdown: "# newer", capturedAt: now.addingTimeInterval(-120))

        let withExclusion = DiffBaselineTracker.agedSelection(
            fromOldestFirst: [old, newer], minimumAge: 60, now: now, excluding: newer.id
        )
        let withoutExclusion = DiffBaselineTracker.agedSelection(
            fromOldestFirst: [old, newer], minimumAge: 60, now: now, excluding: nil
        )

        #expect(withExclusion == old)
        #expect(withoutExclusion == newer)
        #expect(DiffBaselineTracker.agedSelection(fromOldestFirst: [], minimumAge: 60, now: now, excluding: nil) == nil)
    }
}
