import Foundation
import Testing
@testable import minimark

@Suite(.serialized) @MainActor
struct DiffBaselineSelectionControllerTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/selection.md")

    private func makeController(minimumAge: TimeInterval = 60) -> (DiffBaselineSelectionController, DiffBaselineTracker) {
        let tracker = DiffBaselineTracker(minimumAge: minimumAge)
        return (DiffBaselineSelectionController(tracker: tracker), tracker)
    }

    @Test func automaticModeResolvesLikeTheTracker() {
        let (controller, tracker) = makeController()
        var now = Date(timeIntervalSince1970: 1_000_000)
        tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(120)

        let resolved = controller.resolveBaseline(recording: "# v1", for: fileURL, at: now)

        #expect(resolved.markdown == "# v0")
        #expect(controller.activeBaseline == resolved)
        #expect(controller.mode == .automatic)
        #expect(controller.snapshots.map(\.markdown) == ["# v1", "# v0"])
    }

    @Test func pinnedSnapshotWinsOverAutomatic() {
        let (controller, tracker) = makeController()
        var now = Date(timeIntervalSince1970: 1_000_000)
        let v0 = tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(120)
        tracker.record(markdown: "# v1", for: fileURL, at: now)
        now.addTimeInterval(120)

        let pinned = controller.pin(v0.id, for: fileURL)
        let resolved = controller.resolveBaseline(recording: "# v2", for: fileURL, at: now)

        #expect(pinned == v0)
        #expect(resolved == v0)
        #expect(controller.mode == .pinned(v0.id))
        #expect(controller.activeBaseline == v0)
    }

    @Test func evictedPinFallsBackToAutomatic() {
        let tracker = DiffBaselineTracker(minimumAge: 0, maximumHistoryDepth: 2)
        let controller = DiffBaselineSelectionController(tracker: tracker)
        var now = Date(timeIntervalSince1970: 1_000_000)
        let v0 = tracker.record(markdown: "# v0", for: fileURL, at: now)
        _ = controller.pin(v0.id, for: fileURL)

        now.addTimeInterval(1)
        tracker.record(markdown: "# v1", for: fileURL, at: now)
        now.addTimeInterval(1)
        let resolved = controller.resolveBaseline(recording: "# v2", for: fileURL, at: now)

        #expect(controller.mode == .automatic)
        #expect(resolved.markdown == "# v1")
    }

    @Test func pinUnknownIDReturnsNilAndKeepsMode() {
        let (controller, _) = makeController()

        let result = controller.pin(UUID(), for: fileURL)

        #expect(result == nil)
        #expect(controller.mode == .automatic)
        #expect(controller.activeBaseline == nil)
    }

    @Test func selectAutomaticDoesNotRecordAndUsesLookback() {
        let (controller, tracker) = makeController(minimumAge: 60)
        var now = Date(timeIntervalSince1970: 1_000_000)
        let v0 = tracker.record(markdown: "# v0", for: fileURL, at: now)
        now.addTimeInterval(30)
        let v1 = tracker.record(markdown: "# v1", for: fileURL, at: now)
        _ = controller.pin(v1.id, for: fileURL)

        now.addTimeInterval(45)
        let resolved = controller.selectAutomatic(for: fileURL, at: now)

        #expect(resolved == v0)
        #expect(controller.mode == .automatic)
        #expect(tracker.snapshots(for: fileURL).count == 2)
    }

    @Test func selectAutomaticWithEmptyHistoryClearsBaseline() {
        let (controller, _) = makeController()

        let resolved = controller.selectAutomatic(for: fileURL, at: Date())

        #expect(resolved == nil)
        #expect(controller.activeBaseline == nil)
        #expect(controller.snapshots.isEmpty)
    }

    @Test func adoptRecordedBaselineMakesRecordActive() {
        let (controller, tracker) = makeController()
        let now = Date(timeIntervalSince1970: 1_000_000)

        let adopted = controller.adoptRecordedBaseline(markdown: "# before", for: fileURL, at: now)

        #expect(controller.activeBaseline == adopted)
        #expect(tracker.snapshot(id: adopted.id, for: fileURL) == adopted)
        #expect(controller.mode == .automatic)
    }

    @Test func resetForDocumentClearsBaselineButListsExistingHistory() {
        let (controller, tracker) = makeController()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let v0 = tracker.record(markdown: "# v0", for: fileURL, at: now)
        _ = controller.pin(v0.id, for: fileURL)

        controller.resetForDocument(at: fileURL)
        #expect(controller.mode == .automatic)
        #expect(controller.activeBaseline == nil)
        #expect(controller.snapshots == [v0])

        controller.resetForDocument(at: nil)
        #expect(controller.snapshots.isEmpty)
    }
}
