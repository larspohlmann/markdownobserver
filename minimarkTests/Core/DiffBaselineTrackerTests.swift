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

        #expect(result == "# v0")
    }

    @Test func returnsFallbackBaselineWhenNothingIsOldEnough() {
        let tracker = DiffBaselineTracker(minimumAge: 60)
        let fileURL = URL(fileURLWithPath: "/tmp/test.md")
        var now = Date(timeIntervalSince1970: 1_000_000)

        _ = tracker.recordAndSelectBaseline(markdown: "# v0", for: fileURL, at: now)

        now.addTimeInterval(5)
        let result = tracker.recordAndSelectBaseline(markdown: "# v1", for: fileURL, at: now)

        #expect(result == "# v0")
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

        #expect(result == "# v0")
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

        #expect(result == "# v1")
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

        #expect(result == "# same")
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

        #expect(result == "# v4")
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
        #expect(before == "# v0")

        tracker.updateMinimumAge(10)

        now.addTimeInterval(1)
        let after = tracker.recordAndSelectBaseline(markdown: "# v3", for: fileURL, at: now)
        #expect(after == "# v0")
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

        #expect(result == "# fresh")
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

        #expect(resultA == "# A-v0")
        #expect(resultB == "# B-v0")
    }
}
