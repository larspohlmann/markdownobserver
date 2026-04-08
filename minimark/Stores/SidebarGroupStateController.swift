import Foundation
import Observation

@MainActor
@Observable
final class SidebarGroupStateController {

    // MARK: - Mutable Inputs

    var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
        didSet {
            if sortMode != .manualOrder {
                manualGroupOrder = nil
            }
            recomputeGroupingIfNeeded()
        }
    }
    var fileSortMode: ReaderSidebarSortMode = .lastChangedNewestFirst { didSet { recomputeGroupingIfNeeded() } }
    var pinnedGroupIDs: Set<String> = [] { didSet { recomputeGroupingIfNeeded() } }
    var collapsedGroupIDs: Set<String> = []
    var manualGroupOrder: [String]?

    // MARK: - Computed Outputs

    private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    private(set) var groupIndicatorStates: [String: [ReaderDocumentIndicatorState]] = [:]
    private(set) var groupIndicatorPulseTokens: [String: Int] = [:]

    // MARK: - Private

    private var documents: [ReaderSidebarDocumentController.Document] = []
    private var suppressRecompute = false
    private var lastRowStates: [UUID: SidebarRowState] = [:]

    // MARK: - Init

    init() {}

    func configureSortModes(sortMode: ReaderSidebarSortMode, fileSortMode: ReaderSidebarSortMode) {
        suppressRecompute = true
        self.sortMode = sortMode
        self.fileSortMode = fileSortMode
        suppressRecompute = false
    }

    // MARK: - Document Updates

    func updateDocuments(
        _ documents: [ReaderSidebarDocumentController.Document],
        rowStates: [UUID: SidebarRowState] = [:]
    ) {
        self.documents = documents
        self.lastRowStates = rowStates
        suppressRecompute = true
        pruneStaleGroupIDs()
        suppressRecompute = false
        rebuildGroupIndicatorStates()
        recomputeGrouping()
    }

    func observeRowStates(from documentController: ReaderSidebarDocumentController) {
        documentController.onRowStatesChanged = { [weak self] rowStates in
            self?.handleRowStatesChanged(rowStates)
        }
    }

    private func handleRowStatesChanged(_ rowStates: [UUID: SidebarRowState]) {
        guard rowStates != lastRowStates else { return }
        lastRowStates = rowStates
        rebuildGroupIndicatorStates()
        recomputeGrouping()
    }

    // MARK: - Favorites Persistence

    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) {
        suppressRecompute = true
        sortMode = state.groupSortMode
        fileSortMode = state.fileSortMode
        pinnedGroupIDs = state.pinnedGroupIDs
        collapsedGroupIDs = state.collapsedGroupIDs
        suppressRecompute = false
        recomputeGrouping()
    }

    struct WorkspaceStateSnapshot: Equatable {
        let sortMode: ReaderSidebarSortMode
        let fileSortMode: ReaderSidebarSortMode
        let pinnedGroupIDs: Set<String>
        let collapsedGroupIDs: Set<String>
    }

    var persistenceSnapshot: WorkspaceStateSnapshot {
        WorkspaceStateSnapshot(
            sortMode: sortMode,
            fileSortMode: fileSortMode,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs
        )
    }

    // MARK: - Group Expansion

    func isGroupExpanded(_ groupID: String) -> Bool {
        !collapsedGroupIDs.contains(groupID)
    }

    func setGroupExpanded(_ groupID: String, isExpanded: Bool) {
        if isExpanded {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
    }

    func toggleGroupPin(_ groupID: String) {
        if pinnedGroupIDs.contains(groupID) {
            pinnedGroupIDs.remove(groupID)
        } else {
            pinnedGroupIDs.insert(groupID)
        }
    }

    func moveGroup(from sourceIndex: Int, to destinationIndex: Int) {
        guard case .grouped(let groups) = computedGrouping else { return }
        var orderedIDs = groups.map(\.id)
        guard sourceIndex < orderedIDs.count else { return }
        let movedID = orderedIDs.remove(at: sourceIndex)
        let adjustedDestination = min(destinationIndex, orderedIDs.count)
        orderedIDs.insert(movedID, at: adjustedDestination)
        manualGroupOrder = orderedIDs
        sortMode = .manualOrder
    }

    // MARK: - Private

    private func recomputeGroupingIfNeeded() {
        guard !suppressRecompute else { return }
        recomputeGrouping()
    }

    private func recomputeGrouping() {
        recomputeGrouping(sortMode: sortMode, fileSortMode: fileSortMode, pinnedGroupIDs: pinnedGroupIDs)
    }

    private func recomputeGrouping(
        sortMode: ReaderSidebarSortMode,
        fileSortMode: ReaderSidebarSortMode,
        pinnedGroupIDs: Set<String>
    ) {
        let sortedDocuments = fileSortMode.sorted(documents) { document in
            ReaderSidebarSortDescriptor(
                displayName: document.readerStore.fileDisplayName,
                lastChangedAt: document.readerStore.fileLastModifiedAt
                    ?? document.readerStore.lastExternalChangeAt
                    ?? document.readerStore.lastRefreshAt
            )
        }

        let directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]
        if sortMode == .openOrder {
            directoryOrderSourceDocuments = documents
        } else {
            directoryOrderSourceDocuments = sortedDocuments
        }

        computedGrouping = ReaderSidebarGrouping.group(
            sortedDocuments,
            sortMode: sortMode,
            directoryOrderSourceDocuments: directoryOrderSourceDocuments,
            pinnedGroupIDs: pinnedGroupIDs,
            precomputedIndicatorStates: groupIndicatorStates,
            precomputedIndicatorPulseTokens: groupIndicatorPulseTokens
        )

        if sortMode == .manualOrder, let manualOrder = manualGroupOrder,
           case .grouped(let groups) = computedGrouping {
            computedGrouping = .grouped(applyManualOrder(manualOrder, to: groups))
        }
    }

    private func rebuildGroupIndicatorStates() {
        let grouped = Dictionary(grouping: documents) { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false) ?? ""
        }
        var result: [String: [ReaderDocumentIndicatorState]] = [:]
        var updatedPulseTokens = groupIndicatorPulseTokens
        for (path, docs) in grouped {
            let states = docs.compactMap { doc in
                lastRowStates[doc.id]?.indicatorState
            }
            let previous = groupIndicatorStates[path] ?? []
            let next = ReaderSidebarGrouping.indicators(from: states)
            if previous != next, !next.isEmpty {
                updatedPulseTokens[path, default: 0] += 1
            }
            result[path] = next
        }
        groupIndicatorStates = result
        groupIndicatorPulseTokens = updatedPulseTokens.filter { result[$0.key] != nil }
    }

    private func pruneStaleGroupIDs() {
        let activeGroupIDs = Set(documents.compactMap { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false)
        })
        collapsedGroupIDs.formIntersection(activeGroupIDs)
        pinnedGroupIDs.formIntersection(activeGroupIDs)
    }

    private func applyManualOrder(_ manualOrder: [String], to groups: [ReaderSidebarGrouping.Group]) -> [ReaderSidebarGrouping.Group] {
        let groupByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var pinnedManual: [ReaderSidebarGrouping.Group] = []
        var unpinnedManual: [ReaderSidebarGrouping.Group] = []
        var seen = Set<String>()

        for id in manualOrder {
            guard let group = groupByID[id], seen.insert(id).inserted else { continue }
            if group.isPinned {
                pinnedManual.append(group)
            } else {
                unpinnedManual.append(group)
            }
        }

        for group in groups where !seen.contains(group.id) {
            if group.isPinned {
                pinnedManual.append(group)
            } else {
                unpinnedManual.append(group)
            }
        }

        return pinnedManual + unpinnedManual
    }
}
