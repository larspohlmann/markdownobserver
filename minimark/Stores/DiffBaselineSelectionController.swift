import Foundation
import Observation

/// Owns which snapshot the current document is compared to. Pure state:
/// it records and looks up snapshots in the tracker but never renders.
@MainActor
@Observable
final class DiffBaselineSelectionController {
    private(set) var mode: DiffBaselineSelectionMode = .automatic
    /// The snapshot the current changed regions were computed against. `nil` = no comparison.
    private(set) var activeBaseline: DiffBaselineSnapshot?
    /// Snapshots for the current document, newest first.
    private(set) var snapshots: [DiffBaselineSnapshot] = []

    @ObservationIgnored private let tracker: DiffBaselineTracking

    init(tracker: DiffBaselineTracking) {
        self.tracker = tracker
    }

    /// Records `previousMarkdown` and returns the pinned snapshot when pinned and
    /// still present, otherwise the automatic lookback selection. An evicted pin
    /// falls back to automatic mode.
    func resolveBaseline(recording previousMarkdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot {
        let automatic = tracker.recordAndSelectBaseline(markdown: previousMarkdown, for: fileURL, at: now)
        let resolved: DiffBaselineSnapshot
        if case .pinned(let id) = mode, let pinned = tracker.snapshot(id: id, for: fileURL) {
            resolved = pinned
        } else {
            mode = .automatic
            resolved = automatic
        }
        activeBaseline = resolved
        snapshots = tracker.snapshots(for: fileURL)
        return resolved
    }

    /// Records `markdown` and makes that record the active baseline. Used when a
    /// folder-watch auto-open already carries the previous content.
    func adoptRecordedBaseline(markdown: String, for fileURL: URL, at now: Date) -> DiffBaselineSnapshot {
        let recorded = tracker.record(markdown: markdown, for: fileURL, at: now)
        mode = .automatic
        activeBaseline = recorded
        snapshots = tracker.snapshots(for: fileURL)
        return recorded
    }

    /// Pins `id`. Returns the snapshot, or `nil` (state unchanged) when it no longer exists.
    func pin(_ id: DiffBaselineSnapshot.ID, for fileURL: URL) -> DiffBaselineSnapshot? {
        guard let snapshot = tracker.snapshot(id: id, for: fileURL) else {
            return nil
        }
        mode = .pinned(id)
        activeBaseline = snapshot
        snapshots = tracker.snapshots(for: fileURL)
        return snapshot
    }

    /// Returns to automatic mode using the current history without recording.
    func selectAutomatic(for fileURL: URL, at now: Date) -> DiffBaselineSnapshot? {
        mode = .automatic
        let newestFirst = tracker.snapshots(for: fileURL)
        snapshots = newestFirst
        activeBaseline = DiffBaselineTracker.agedSelection(
            fromOldestFirst: Array(newestFirst.reversed()),
            minimumAge: tracker.currentMinimumAge,
            now: now,
            excluding: nil
        )
        return activeBaseline
    }

    /// Called on open without a baseline and on close. Existing history for
    /// `fileURL` stays listed so the user can compare against it on demand.
    func resetForDocument(at fileURL: URL?) {
        mode = .automatic
        activeBaseline = nil
        snapshots = fileURL.map { tracker.snapshots(for: $0) } ?? []
    }
}
