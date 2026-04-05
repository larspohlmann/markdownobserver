import Foundation

@MainActor
@Observable
final class SidebarGroupStateController {

    // MARK: - Mutable Inputs

    var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst { didSet { recomputeGroupingIfNeeded() } }
    var fileSortMode: ReaderSidebarSortMode = .lastChangedNewestFirst { didSet { recomputeGroupingIfNeeded() } }
    var pinnedGroupIDs: Set<String> = [] { didSet { recomputeGroupingIfNeeded() } }
    var collapsedGroupIDs: Set<String> = []

    // MARK: - Computed Outputs

    private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    private(set) var groupIndicatorStates: [String: ReaderDocumentIndicatorState] = [:]

    // MARK: - Private

    private var documents: [ReaderSidebarDocumentController.Document] = []
    private var suppressRecompute = false
    private var lastRowStates: [UUID: SidebarRowState] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Document Updates

    func updateDocuments(
        _ documents: [ReaderSidebarDocumentController.Document],
        rowStates: [UUID: SidebarRowState] = [:]
    ) {
        self.documents = documents
        self.lastRowStates = rowStates
        pruneStaleGroupIDs()
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

    struct WorkspaceStateSnapshot {
        let sortMode: ReaderSidebarSortMode
        let fileSortMode: ReaderSidebarSortMode
        let pinnedGroupIDs: Set<String>
        let collapsedGroupIDs: Set<String>
    }

    func workspaceStateSnapshot() -> WorkspaceStateSnapshot {
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
            precomputedIndicatorStates: groupIndicatorStates
        )
    }

    private func rebuildGroupIndicatorStates() {
        let grouped = Dictionary(grouping: documents) { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false) ?? ""
        }
        var result: [String: ReaderDocumentIndicatorState] = [:]
        for (path, docs) in grouped {
            let states = docs.compactMap { doc in
                lastRowStates[doc.id]?.indicatorState
            }
            result[path] = ReaderSidebarGrouping.aggregatedIndicatorState(from: states)
        }
        groupIndicatorStates = result
    }

    private func pruneStaleGroupIDs() {
        let activeGroupIDs = Set(documents.compactMap { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false)
        })
        collapsedGroupIDs.formIntersection(activeGroupIDs)
        pinnedGroupIDs.formIntersection(activeGroupIDs)
    }
}
