import Foundation

@MainActor
final class SidebarObservationManager {
    typealias Document = SidebarDocumentController.Document

    private var documentObservationTasks: [UUID: Task<Void, Never>] = [:]
    private var selectedStoreObservationTask: Task<Void, Never>?
    private var selectedStoreBindingGeneration: UInt = 0
    private var needsInitialSetup = true

    deinit {
        selectedStoreObservationTask?.cancel()
        for task in documentObservationTasks.values { task.cancel() }
    }

    func ensureSetup(
        for documents: [Document],
        onStoreChanged: @escaping @MainActor (UUID) -> Void
    ) {
        guard needsInitialSetup else { return }
        needsInitialSetup = false
        synchronize(for: documents, onStoreChanged: onStoreChanged)
    }

    func synchronize(
        for documents: [Document],
        onStoreChanged: @escaping @MainActor (UUID) -> Void
    ) {
        let currentIDs = Set(documents.map(\.id))

        for documentID in documentObservationTasks.keys where !currentIDs.contains(documentID) {
            documentObservationTasks[documentID]?.cancel()
            documentObservationTasks[documentID] = nil
        }

        for document in documents where documentObservationTasks[document.id] == nil {
            let documentID = document.id
            document.documentStore.externalChange.onStateChanged = {
                onStoreChanged(documentID)
            }
            documentObservationTasks[document.id] = Task { [weak self] in
                let store = document.documentStore
                defer { store.externalChange.onStateChanged = nil }
                while !Task.isCancelled {
                    let cancelled = await ObservationAsyncChange.next {
                        _ = store.document.fileDisplayName
                        _ = store.document.fileLastModifiedAt
                        _ = store.externalChange.lastExternalChangeAt
                        _ = store.renderingController.lastRefreshAt
                        _ = store.document.isCurrentFileMissing
                        _ = store.externalChange.hasUnacknowledgedExternalChange
                    }
                    if cancelled { break }
                    guard self != nil else { break }
                    onStoreChanged(documentID)
                }
            }
        }
    }

    func bindSelectedStore(
        _ store: DocumentStore,
        onChange: @escaping @MainActor () -> Void
    ) {
        selectedStoreBindingGeneration &+= 1
        let generation = selectedStoreBindingGeneration

        selectedStoreObservationTask?.cancel()
        selectedStoreObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                let cancelled = await ObservationAsyncChange.next {
                    _ = store.document.windowTitle
                    _ = store.document.fileURL
                    _ = store.externalChange.hasUnacknowledgedExternalChange
                }
                if cancelled { break }
                guard let self,
                      self.selectedStoreBindingGeneration == generation else { break }
                onChange()
            }
        }
    }
}
