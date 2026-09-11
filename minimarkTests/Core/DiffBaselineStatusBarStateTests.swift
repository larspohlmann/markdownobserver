import Foundation
import Testing
@testable import minimark

@Suite
struct DiffBaselineStatusBarStateTests {
    private let now = Date(timeIntervalSince1970: 1_789_137_125)

    private func snapshots() -> [DiffBaselineSnapshot] {
        [
            DiffBaselineSnapshot(markdown: "# v1", capturedAt: now.addingTimeInterval(-30)),
            DiffBaselineSnapshot(markdown: "# v0", capturedAt: now.addingTimeInterval(-300))
        ]
    }

    @Test func hiddenWithoutDocument() {
        let state = DiffBaselineStatusBarState.make(
            hasOpenDocument: false, isSourceEditing: false, mode: .automatic,
            activeBaseline: nil, snapshots: [], lookback: .twoMinutes, now: now
        )
        #expect(state.isVisible == false)
        #expect(state.isEnabled == false)
    }

    @Test func automaticMarksBothAutomaticAndResolvedSnapshot() {
        let list = snapshots()
        let state = DiffBaselineStatusBarState.make(
            hasOpenDocument: true, isSourceEditing: false, mode: .automatic,
            activeBaseline: list[1], snapshots: list, lookback: .twoMinutes, now: now
        )
        #expect(state.isVisible)
        #expect(state.isEnabled)
        #expect(state.isAutomatic)
        #expect(state.automaticTitle == "Automatic (lookback 2 minutes)")
        #expect(state.items.map(\.isActive) == [false, true])
        #expect(state.items.map(\.id) == list.map(\.id))
        #expect(state.label.hasPrefix("Comparing to "))
    }

    @Test func pinnedMarksOnlyThePinnedSnapshot() {
        let list = snapshots()
        let state = DiffBaselineStatusBarState.make(
            hasOpenDocument: true, isSourceEditing: false, mode: .pinned(list[0].id),
            activeBaseline: list[0], snapshots: list, lookback: .tenMinutes, now: now
        )
        #expect(state.isAutomatic == false)
        #expect(state.items.map(\.isActive) == [true, false])
    }

    @Test func disabledWhileEditingOrWithoutSnapshots() {
        let editing = DiffBaselineStatusBarState.make(
            hasOpenDocument: true, isSourceEditing: true, mode: .automatic,
            activeBaseline: nil, snapshots: snapshots(), lookback: .twoMinutes, now: now
        )
        #expect(editing.isVisible)
        #expect(editing.isEnabled == false)

        let empty = DiffBaselineStatusBarState.make(
            hasOpenDocument: true, isSourceEditing: false, mode: .automatic,
            activeBaseline: nil, snapshots: [], lookback: .twoMinutes, now: now
        )
        #expect(empty.isEnabled == false)
        #expect(empty.label == "No earlier snapshot")
        #expect(empty.items.isEmpty)
    }
}
