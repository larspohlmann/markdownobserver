import Foundation

struct DiffBaselineStatusBarState: Equatable {
    struct Item: Identifiable, Equatable {
        let id: DiffBaselineSnapshot.ID
        let title: String
        let isActive: Bool
    }

    let isVisible: Bool
    let isEnabled: Bool
    let label: String
    let automaticTitle: String
    let isAutomatic: Bool
    let items: [Item]

    static let hidden = DiffBaselineStatusBarState(
        isVisible: false, isEnabled: false, label: "", automaticTitle: "", isAutomatic: true, items: []
    )

    static func make(
        hasOpenDocument: Bool,
        isSourceEditing: Bool,
        mode: DiffBaselineSelectionMode,
        activeBaseline: DiffBaselineSnapshot?,
        snapshots: [DiffBaselineSnapshot],
        lookback: DiffBaselineLookback,
        now: Date
    ) -> DiffBaselineStatusBarState {
        guard hasOpenDocument else { return .hidden }

        let isAutomatic: Bool
        if case .automatic = mode { isAutomatic = true } else { isAutomatic = false }

        return DiffBaselineStatusBarState(
            isVisible: true,
            isEnabled: !isSourceEditing && !snapshots.isEmpty,
            label: DiffBaselineSnapshotFormatter.statusLabel(
                activeBaseline: activeBaseline, hasSnapshots: !snapshots.isEmpty, relativeTo: now
            ),
            automaticTitle: "Automatic (lookback \(lookback.displayName))",
            isAutomatic: isAutomatic,
            items: snapshots.map { snapshot in
                Item(
                    id: snapshot.id,
                    title: DiffBaselineSnapshotFormatter.menuTitle(for: snapshot, relativeTo: now),
                    isActive: snapshot.id == activeBaseline?.id
                )
            }
        )
    }
}
