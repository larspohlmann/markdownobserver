import Combine
import Foundation

@MainActor
final class SidebarGroupStateController: ObservableObject {

    // MARK: - Mutable Inputs

    @Published var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst
    @Published var pinnedGroupIDs: Set<String> = []
    @Published var collapsedGroupIDs: Set<String> = []

    // MARK: - Computed Outputs

    @Published private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    @Published private(set) var groupIndicatorStates: [String: ReaderDocumentIndicatorState] = [:]

    // MARK: - Private

    private var documents: [ReaderSidebarDocumentController.Document] = []
    private var recomputeCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        subscribeToArrangementChanges()
    }

    // MARK: - Document Updates

    func updateDocuments(_ documents: [ReaderSidebarDocumentController.Document]) {
        self.documents = documents
        pruneStaleGroupIDs()
        rebuildGroupIndicatorStates()
        recomputeGrouping()
    }

    // MARK: - Favorites Persistence

    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) {
        recomputeCancellable = nil
        sortMode = state.groupSortMode
        pinnedGroupIDs = state.pinnedGroupIDs
        collapsedGroupIDs = state.collapsedGroupIDs
        recomputeGrouping()
        subscribeToArrangementChanges()
    }

    struct WorkspaceStateSnapshot {
        let sortMode: ReaderSidebarSortMode
        let pinnedGroupIDs: Set<String>
        let collapsedGroupIDs: Set<String>
    }

    func workspaceStateSnapshot() -> WorkspaceStateSnapshot {
        WorkspaceStateSnapshot(
            sortMode: sortMode,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs
        )
    }

    // MARK: - Group Expansion

    func isGroupExpanded(_ groupID: String) -> Bool {
        !collapsedGroupIDs.contains(groupID)
    }

    func toggleGroupExpansion(_ groupID: String) {
        if collapsedGroupIDs.contains(groupID) {
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

    private func subscribeToArrangementChanges() {
        recomputeCancellable = Publishers.CombineLatest(
            $sortMode,
            $pinnedGroupIDs
        )
        .dropFirst()
        .sink { [weak self] sortMode, pinnedGroupIDs in
            self?.recomputeGrouping(sortMode: sortMode, pinnedGroupIDs: pinnedGroupIDs)
        }
    }

    private func recomputeGrouping() {
        recomputeGrouping(sortMode: sortMode, pinnedGroupIDs: pinnedGroupIDs)
    }

    private func recomputeGrouping(
        sortMode: ReaderSidebarSortMode,
        pinnedGroupIDs: Set<String>
    ) {
        computedGrouping = ReaderSidebarGrouping.group(
            documents,
            sortMode: sortMode,
            directoryOrderSourceDocuments: documents,
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
            let states = docs.map { doc in
                ReaderDocumentIndicatorState(
                    hasUnacknowledgedExternalChange: doc.readerStore.hasUnacknowledgedExternalChange,
                    isCurrentFileMissing: doc.readerStore.isCurrentFileMissing
                )
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
