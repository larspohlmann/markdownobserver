import Foundation

@MainActor
final class DockTileController {
    static let shared = DockTileController()

    private(set) var createdCount = 0
    private(set) var modifiedCount = 0
    private(set) var deletedCount = 0

    var onCountsChanged: ((_ created: Int, _ modified: Int, _ deleted: Int) -> Void)?

    private var rowStatesByWindow: [UUID: [UUID: SidebarRowState]] = [:]

    init() {}

    func updateRowStates(for windowToken: UUID, rowStates: [UUID: SidebarRowState]) {
        rowStatesByWindow[windowToken] = rowStates
        recomputeCounts()
    }

    func removeRowStates(for windowToken: UUID) {
        rowStatesByWindow.removeValue(forKey: windowToken)
        recomputeCounts()
    }

    private func recomputeCounts() {
        var created = 0
        var modified = 0
        var deleted = 0

        for (_, rowStates) in rowStatesByWindow {
            for (_, state) in rowStates {
                switch state.indicatorState {
                case .addedExternalChange:
                    created += 1
                case .externalChange:
                    modified += 1
                case .deletedExternalChange:
                    deleted += 1
                case .none:
                    break
                }
            }
        }

        let changed = created != createdCount || modified != modifiedCount || deleted != deletedCount
        createdCount = created
        modifiedCount = modified
        deletedCount = deleted

        if changed {
            onCountsChanged?(created, modified, deleted)
        }
    }

    func resetForTesting() {
        rowStatesByWindow.removeAll()
        createdCount = 0
        modifiedCount = 0
        deletedCount = 0
        onCountsChanged = nil
    }
}
