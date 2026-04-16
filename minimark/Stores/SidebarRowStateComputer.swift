import Foundation
import Observation

@MainActor
@Observable
final class SidebarRowStateComputer {
    typealias Document = ReaderSidebarDocumentController.Document

    private(set) var rowStates: [UUID: SidebarRowState] = [:]
    @ObservationIgnored private var pulseTokens: [UUID: Int] = [:]
    @ObservationIgnored var onRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?
    @ObservationIgnored var onDockTileRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?

    func rebuildAllRowStates(from documents: [Document]) {
        var states: [UUID: SidebarRowState] = [:]
        for document in documents {
            let previousIndicatorState = rowStates[document.id]?.indicatorState
            let currentIndicatorState = deriveIndicatorState(from: document.readerStore)
            if let previousIndicatorState,
               previousIndicatorState != currentIndicatorState,
               currentIndicatorState.showsIndicator {
                pulseTokens[document.id, default: 0] += 1
            }
            states[document.id] = deriveRowState(from: document)
        }
        pulseTokens = pulseTokens.filter { states[$0.key] != nil }
        guard states != rowStates else { return }
        rowStates = states
        onRowStatesChanged?(states)
        onDockTileRowStatesChanged?(states)
    }

    func updateRowStateIfNeeded(for documentID: UUID, in documents: [Document]) {
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        let previousIndicatorState = rowStates[documentID]?.indicatorState
        let currentIndicatorState = deriveIndicatorState(from: document.readerStore)
        if let previousIndicatorState,
           previousIndicatorState != currentIndicatorState,
           currentIndicatorState.showsIndicator {
            pulseTokens[documentID, default: 0] += 1
        }
        let state = deriveRowState(from: document)
        if rowStates[documentID] != state {
            rowStates[documentID] = state
            onRowStatesChanged?(rowStates)
            onDockTileRowStatesChanged?(rowStates)
        }
    }

    func deriveRowState(from document: Document) -> SidebarRowState {
        let store = document.readerStore
        let indicatorState = deriveIndicatorState(from: store)
        return SidebarRowState(
            id: document.id,
            title: store.fileDisplayName.isEmpty ? "Untitled" : store.fileDisplayName,
            lastModified: store.fileLastModifiedAt,
            sortDate: store.fileLastModifiedAt ?? store.lastExternalChangeAt ?? store.lastRefreshAt,
            isFileMissing: store.isCurrentFileMissing,
            indicatorState: indicatorState,
            indicatorPulseToken: pulseTokens[document.id] ?? 0
        )
    }

    private func deriveIndicatorState(from store: ReaderStore) -> ReaderDocumentIndicatorState {
        ReaderDocumentIndicatorState(
            hasUnacknowledgedExternalChange: store.hasUnacknowledgedExternalChange,
            isCurrentFileMissing: store.isCurrentFileMissing,
            unacknowledgedExternalChangeKind: store.externalChange.unacknowledgedExternalChangeKind
        )
    }
}
