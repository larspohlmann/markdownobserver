import Foundation

@MainActor
protocol FileOpenPlanExecutorDelegate: AnyObject {
    typealias Document = SidebarDocumentController.Document

    var selectedDocumentID: UUID { get set }
    var selectedDocumentStore: DocumentStore { get }
    var storeConfigurator: ((DocumentStore) -> Void)? { get }
    func makeDocument() -> Document
    func selectDocument(_ documentID: UUID?)
    func bindSelectedStore()
    func resolvedFolderWatchSession(
        for fileURL: URL,
        requestedSession: FolderWatchSession?
    ) -> FolderWatchSession?
}

@MainActor
final class FileOpenPlanExecutor {
    typealias Document = SidebarDocumentController.Document

    private let documentList: SidebarDocumentList
    private let observationManager: SidebarObservationManager
    private let rowStateComputer: SidebarRowStateComputer
    weak var delegate: FileOpenPlanExecutorDelegate?

    init(
        documentList: SidebarDocumentList,
        observationManager: SidebarObservationManager,
        rowStateComputer: SidebarRowStateComputer
    ) {
        self.documentList = documentList
        self.observationManager = observationManager
        self.rowStateComputer = rowStateComputer
    }

    // MARK: - Public API

    func executePlan(_ plan: FileOpenPlan) {
        guard let delegate else { return }

        observationManager.ensureSetup(
            for: documentList.documents,
            onStoreChanged: makeStoreChangedHandler()
        )
        guard !plan.assignments.isEmpty else { return }

        var didAppendDocuments = false

        for assignment in plan.assignments {
            let fileURL = assignment.fileURL

            if let existingDocument = documentList.document(for: fileURL) {
                if existingDocument.documentStore.document.isDeferredDocument, assignment.loadMode == .loadFully {
                    let store = existingDocument.documentStore
                    let effectiveSession = delegate.resolvedFolderWatchSession(
                        for: fileURL,
                        requestedSession: plan.folderWatchSession
                    )
                    scheduleLoadWithOverlay(on: store) {
                        store.opener.materializeDeferred(
                            origin: plan.origin,
                            folderWatchSession: effectiveSession,
                            initialDiffBaselineMarkdown: assignment.initialDiffBaselineMarkdown
                        )
                    }
                }
                delegate.selectDocument(existingDocument.id)
                continue
            }

            let effectiveFolderWatchSession = delegate.resolvedFolderWatchSession(
                for: fileURL,
                requestedSession: plan.folderWatchSession
            )

            let targetDocument: Document
            let shouldAppendDocument: Bool

            switch assignment.target {
            case .reuseExisting(let documentID):
                if let existing = documentList.documents.first(where: { $0.id == documentID }) {
                    targetDocument = existing
                    shouldAppendDocument = false
                } else {
                    let document = delegate.makeDocument()
                    if let storeConfigurator = delegate.storeConfigurator {
                        storeConfigurator(document.documentStore)
                    }
                    targetDocument = document
                    shouldAppendDocument = true
                }

            case .createNew:
                let document = delegate.makeDocument()
                if let storeConfigurator = delegate.storeConfigurator {
                    storeConfigurator(document.documentStore)
                }
                targetDocument = document
                shouldAppendDocument = true
            }

            switch assignment.loadMode {
            case .deferOnly:
                targetDocument.documentStore.opener.deferFile(
                    at: fileURL,
                    origin: plan.origin,
                    folderWatchSession: effectiveFolderWatchSession
                )
            case .loadFully:
                targetDocument.documentStore.opener.open(
                    at: fileURL,
                    origin: plan.origin,
                    folderWatchSession: effectiveFolderWatchSession,
                    initialDiffBaselineMarkdown: assignment.initialDiffBaselineMarkdown
                )
            }

            guard targetDocument.documentStore.document.fileURL != nil else {
                continue
            }

            if shouldAppendDocument {
                var documentToInsert = targetDocument
                documentToInsert.normalizedFileURL = fileURL
                documentList.append(documentToInsert)
                didAppendDocuments = true
            } else {
                documentList.updateNormalizedURL(for: targetDocument.id, to: fileURL)
            }

            delegate.selectedDocumentID = targetDocument.id
        }

        if didAppendDocuments {
            synchronizeAndRebuild()
        }

        // In screenshot mode, override selection to a specific document by filename
        if let targetFile = ProcessInfo.processInfo.environment["MINIMARK_SCREENSHOT_SELECT_FILE"],
           let match = documentList.documents.first(where: { $0.documentStore.document.fileURL?.lastPathComponent == targetFile }) {
            delegate.selectedDocumentID = match.id
        }

        applyMaterializationStrategy(plan.materializationStrategy)
        delegate.bindSelectedStore()
    }

    func selectDocumentWithNewestModificationDate() {
        let newest = documentList.documents
            .filter { $0.documentStore.document.fileURL != nil }
            .max(by: {
                ($0.documentStore.document.fileLastModifiedAt ?? .distantPast) < ($1.documentStore.document.fileLastModifiedAt ?? .distantPast)
            })
        if let newest {
            delegate?.selectDocument(newest.id)
        }
    }

    func materializeNewestDeferredDocuments(
        count: Int = FolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    ) {
        let deferredDocs = documentList.documents
            .filter { $0.documentStore.document.isDeferredDocument }
            .sorted {
                ($0.documentStore.document.fileLastModifiedAt ?? .distantPast) > ($1.documentStore.document.fileLastModifiedAt ?? .distantPast)
            }

        for document in deferredDocs.prefix(count) {
            document.documentStore.opener.materializeDeferred()
        }

        selectDocumentWithNewestModificationDate()
    }

    // MARK: - Private

    private func applyMaterializationStrategy(_ strategy: FileOpenRequest.MaterializationStrategy) {
        guard let delegate else { return }
        switch strategy {
        case .loadAll, .deferOnly:
            break
        case .deferThenMaterializeNewest(let count):
            materializeNewestDeferredDocuments(count: count)
        case .deferThenMaterializeSelected:
            if delegate.selectedDocumentStore.document.isDeferredDocument {
                let store = delegate.selectedDocumentStore
                scheduleLoadWithOverlay(on: store) {
                    store.opener.materializeDeferred()
                }
            }
        }
    }

    private func scheduleLoadWithOverlay(on store: DocumentStore, load: @escaping @MainActor () -> Void) {
        store.document.transitionToLoading()
        Task { @MainActor in
            await Task.yield()
            load()
            store.document.holdLoadingOverlayBriefly()
        }
    }

    private func synchronizeAndRebuild() {
        observationManager.synchronize(
            for: documentList.documents,
            onStoreChanged: makeStoreChangedHandler()
        )
        rowStateComputer.rebuildAllRowStates(from: documentList.documents)
    }

    private func makeStoreChangedHandler() -> @MainActor (UUID) -> Void {
        return { [weak self] documentID in
            guard let self else { return }
            self.rowStateComputer.updateRowStateIfNeeded(
                for: documentID,
                in: self.documentList.documents
            )
        }
    }
}
