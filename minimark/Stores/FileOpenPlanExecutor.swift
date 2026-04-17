import Foundation

@MainActor
protocol FileOpenPlanExecutorDelegate: AnyObject {
    typealias Document = ReaderSidebarDocumentController.Document

    var selectedDocumentID: UUID { get set }
    var selectedReaderStore: ReaderStore { get }
    var storeConfigurator: ((ReaderStore) -> Void)? { get }
    func makeDocument() -> Document
    func selectDocument(_ documentID: UUID?)
    func bindSelectedStore()
    func resolvedFolderWatchSession(
        for fileURL: URL,
        requestedSession: ReaderFolderWatchSession?
    ) -> ReaderFolderWatchSession?
}

@MainActor
final class FileOpenPlanExecutor {
    typealias Document = ReaderSidebarDocumentController.Document

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
                if existingDocument.readerStore.document.isDeferredDocument, assignment.loadMode == .loadFully {
                    let store = existingDocument.readerStore
                    let effectiveSession = delegate.resolvedFolderWatchSession(
                        for: fileURL,
                        requestedSession: plan.folderWatchSession
                    )
                    scheduleLoadWithOverlay(on: store) {
                        store.materializeDeferredDocument(
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
                        storeConfigurator(document.readerStore)
                    }
                    targetDocument = document
                    shouldAppendDocument = true
                }

            case .createNew:
                let document = delegate.makeDocument()
                if let storeConfigurator = delegate.storeConfigurator {
                    storeConfigurator(document.readerStore)
                }
                targetDocument = document
                shouldAppendDocument = true
            }

            switch assignment.loadMode {
            case .deferOnly:
                targetDocument.readerStore.deferFile(
                    at: fileURL,
                    origin: plan.origin,
                    folderWatchSession: effectiveFolderWatchSession
                )
            case .loadFully:
                targetDocument.readerStore.openFile(
                    at: fileURL,
                    origin: plan.origin,
                    folderWatchSession: effectiveFolderWatchSession,
                    initialDiffBaselineMarkdown: assignment.initialDiffBaselineMarkdown
                )
            }

            guard targetDocument.readerStore.document.fileURL != nil else {
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
           let match = documentList.documents.first(where: { $0.readerStore.document.fileURL?.lastPathComponent == targetFile }) {
            delegate.selectedDocumentID = match.id
        }

        applyMaterializationStrategy(plan.materializationStrategy)
        delegate.bindSelectedStore()
    }

    func selectDocumentWithNewestModificationDate() {
        let newest = documentList.documents
            .filter { $0.readerStore.document.fileURL != nil }
            .max(by: {
                ($0.readerStore.document.fileLastModifiedAt ?? .distantPast) < ($1.readerStore.document.fileLastModifiedAt ?? .distantPast)
            })
        if let newest {
            delegate?.selectDocument(newest.id)
        }
    }

    func materializeNewestDeferredDocuments(
        count: Int = FolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    ) {
        let deferredDocs = documentList.documents
            .filter { $0.readerStore.document.isDeferredDocument }
            .sorted {
                ($0.readerStore.document.fileLastModifiedAt ?? .distantPast) > ($1.readerStore.document.fileLastModifiedAt ?? .distantPast)
            }

        for document in deferredDocs.prefix(count) {
            document.readerStore.materializeDeferredDocument()
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
            if delegate.selectedReaderStore.document.isDeferredDocument {
                let store = delegate.selectedReaderStore
                scheduleLoadWithOverlay(on: store) {
                    store.materializeDeferredDocument()
                }
            }
        }
    }

    private func scheduleLoadWithOverlay(on store: ReaderStore, load: @escaping @MainActor () -> Void) {
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
