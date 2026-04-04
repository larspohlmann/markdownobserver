import Foundation
import Combine

@MainActor
final class ReaderSidebarDocumentController: ObservableObject {
    struct Document: Identifiable {
        let id: UUID
        let readerStore: ReaderStore
    }

    @Published private(set) var documents: [Document]
    @Published var selectedDocumentID: UUID
    @Published private(set) var selectedWindowTitle: String
    @Published private(set) var selectedFileURL: URL?
    @Published private(set) var selectedHasUnacknowledgedExternalChange: Bool
    @Published private(set) var selectedFolderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    @Published var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?
    @Published private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    @Published private(set) var isFolderWatchInitialScanInProgress: Bool
    @Published private(set) var didFolderWatchInitialScanFail: Bool
    @Published private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress?
    @Published private(set) var scannedFileCount: Int?

    private let makeReaderStore: () -> ReaderStore
    private let folderWatchController: ReaderFolderWatchController
    private let selectedStoreProjection = ReaderSidebarSelectedStoreProjection()
    private var storeConfigurator: ((ReaderStore) -> Void)?
    private var selectedStoreBindingGeneration: UInt = 0
    private var documentChangeCancellables: [UUID: AnyCancellable] = [:]
    lazy var fileOpenCoordinator = FileOpenCoordinator(controller: self)

    init(
        settingsStore: ReaderSettingsStore,
        makeReaderStore: (() -> ReaderStore)? = nil,
        makeFolderWatchController: (() -> ReaderFolderWatchController)? = nil
    ) {
        let resolvedMakeReaderStore = makeReaderStore ?? {
            ReaderStore(settingsStore: settingsStore)
        }
        self.makeReaderStore = resolvedMakeReaderStore
        self.folderWatchController = makeFolderWatchController?() ?? ReaderFolderWatchController(settingsStore: settingsStore)

        let initialDocument = Document(id: UUID(), readerStore: resolvedMakeReaderStore())
        documents = [initialDocument]
        selectedDocumentID = initialDocument.id
        selectedWindowTitle = initialDocument.readerStore.windowTitle
        selectedFileURL = initialDocument.readerStore.fileURL
        selectedHasUnacknowledgedExternalChange = initialDocument.readerStore.hasUnacknowledgedExternalChange
        selectedFolderWatchAutoOpenWarning = nil
        activeFolderWatchSession = nil
        isFolderWatchInitialScanInProgress = false
        didFolderWatchInitialScanFail = false
        contentScanProgress = nil
        scannedFileCount = nil
        synchronizeDocumentChangeObservers()
        configureFolderWatchController()
        bindSelectedStore()
    }

    var selectedDocument: Document? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    var selectedReaderStore: ReaderStore {
        selectedDocument?.readerStore ?? documents[0].readerStore
    }

    var canStopFolderWatch: Bool {
        activeFolderWatchSession != nil
    }

    func setStoreConfigurator(_ configurator: @escaping (ReaderStore) -> Void) {
        storeConfigurator = configurator
        for document in documents {
            configurator(document.readerStore)
        }
    }

    func selectDocument(_ documentID: UUID?) {
        guard let documentID,
              documents.contains(where: { $0.id == documentID }) else {
            return
        }

        if selectedDocumentID == documentID {
            return
        }

        selectedDocumentID = documentID
        let store = selectedReaderStore

        if store.isDeferredDocument {
            scheduleLoadWithOverlay(on: store) {
                store.materializeDeferredDocument()
            }
            bindSelectedStore()
        } else {
            bindSelectedStore()
        }
    }

    @discardableResult
    func focusDocument(at fileURL: URL) -> Bool {
        guard let existingDocument = document(for: fileURL) else {
            return false
        }

        selectDocument(existingDocument.id)
        return true
    }

    func selectDocumentWithNewestModificationDate() {
        let newest = documents
            .filter { $0.readerStore.fileURL != nil }
            .max(by: {
                ($0.readerStore.fileLastModifiedAt ?? .distantPast) < ($1.readerStore.fileLastModifiedAt ?? .distantPast)
            })
        if let newest {
            selectDocument(newest.id)
        }
    }

    func materializeNewestDeferredDocuments(
        count: Int = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    ) {
        let deferredDocs = documents
            .filter { $0.readerStore.isDeferredDocument }
            .sorted {
                ($0.readerStore.fileLastModifiedAt ?? .distantPast) > ($1.readerStore.fileLastModifiedAt ?? .distantPast)
            }

        for document in deferredDocs.prefix(count) {
            document.readerStore.materializeDeferredDocument()
        }

        selectDocumentWithNewestModificationDate()
    }

    func executePlan(_ plan: FileOpenPlan) {
        guard !plan.assignments.isEmpty else { return }

        var didAppendDocuments = false

        for assignment in plan.assignments {
            // assignment.fileURL is already normalized by FileOpenCoordinator.deduplicateAndSort
            let fileURL = assignment.fileURL

            if let existingDocument = document(for: fileURL) {
                if existingDocument.readerStore.isDeferredDocument, assignment.loadMode == .loadFully {
                    let store = existingDocument.readerStore
                    let effectiveSession = resolvedFolderWatchSession(
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
                selectDocument(existingDocument.id)
                continue
            }

            let effectiveFolderWatchSession = resolvedFolderWatchSession(
                for: fileURL,
                requestedSession: plan.folderWatchSession
            )

            let targetDocument: Document
            let shouldAppendDocument: Bool

            switch assignment.target {
            case .reuseExisting(let documentID):
                if let existing = documents.first(where: { $0.id == documentID }) {
                    targetDocument = existing
                    shouldAppendDocument = false
                } else {
                    let document = makeDocument()
                    if let storeConfigurator {
                        storeConfigurator(document.readerStore)
                    }
                    targetDocument = document
                    shouldAppendDocument = true
                }

            case .createNew:
                let document = makeDocument()
                if let storeConfigurator {
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

            guard targetDocument.readerStore.fileURL != nil else {
                continue
            }

            if shouldAppendDocument {
                documents.append(targetDocument)
                didAppendDocuments = true
            }

            selectedDocumentID = targetDocument.id
        }

        if didAppendDocuments {
            synchronizeDocumentChangeObservers()
        }

        applyMaterializationStrategy(plan.materializationStrategy)
        bindSelectedStore()
    }

    private func applyMaterializationStrategy(_ strategy: FileOpenRequest.MaterializationStrategy) {
        switch strategy {
        case .loadAll:
            break
        case .deferThenMaterializeNewest(let count):
            materializeNewestDeferredDocuments(count: count)
        case .deferThenMaterializeSelected:
            if selectedReaderStore.isDeferredDocument {
                let store = selectedReaderStore
                scheduleLoadWithOverlay(on: store) {
                    store.materializeDeferredDocument()
                }
            }
        }
    }

    func closeDocument(_ documentID: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == documentID }) else {
            return
        }

        documents.remove(at: index)
        synchronizeDocumentChangeObservers()

        if documents.isEmpty {
            let replacement = makeDocument()
            documents = [replacement]
            synchronizeDocumentChangeObservers()
            if let storeConfigurator {
                storeConfigurator(replacement.readerStore)
            }
            selectedDocumentID = replacement.id
            bindSelectedStore()
            return
        }

        if selectedDocumentID == documentID {
            let nextIndex = min(index, documents.count - 1)
            selectedDocumentID = documents[nextIndex].id
        }

        bindSelectedStore()
    }

    func closeOtherDocuments(keeping documentID: UUID) {
        closeOtherDocuments(keeping: [documentID])
    }

    func closeOtherDocuments(keeping documentIDs: Set<UUID>) {
        let retainedDocuments = documents.filter { documentIDs.contains($0.id) }
        guard !retainedDocuments.isEmpty else {
            return
        }

        documents = retainedDocuments
        synchronizeDocumentChangeObservers()

        if !retainedDocuments.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = retainedDocuments[0].id
        }

        bindSelectedStore()
    }

    func closeDocuments(_ documentIDs: Set<UUID>) {
        guard !documentIDs.isEmpty else {
            return
        }

        let removedDocuments = documents.filter { documentIDs.contains($0.id) }
        guard !removedDocuments.isEmpty else {
            return
        }

        if removedDocuments.count >= documents.count {
            closeAllDocuments()
            return
        }

        let remainingDocuments = documents.filter { !documentIDs.contains($0.id) }
        documents = remainingDocuments
        synchronizeDocumentChangeObservers()

        if !remainingDocuments.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = remainingDocuments[0].id
        }

        bindSelectedStore()
    }

    func closeAllDocuments() {
        let replacement = makeDocument()
        if let storeConfigurator {
            storeConfigurator(replacement.readerStore)
        }

        documents = [replacement]
        synchronizeDocumentChangeObservers()
        selectedDocumentID = replacement.id
        bindSelectedStore()
    }

    func startWatchingFolder(
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) throws {
        try folderWatchController.startWatching(
            folderURL: folderURL,
            options: options,
            performInitialAutoOpen: performInitialAutoOpen
        )
    }

    func scanCurrentMarkdownFiles(completion: @escaping @MainActor ([URL]) -> Void) {
        folderWatchController.scanCurrentMarkdownFiles(completion: completion)
    }

    func stopFolderWatch() {
        folderWatchController.stopWatching()
    }

    func stopWatchingFolders(_ documentIDs: Set<UUID>) {
        guard documentIDs.contains(where: { documentID in
            guard let document = documents.first(where: { $0.id == documentID }) else {
                return false
            }

            return folderWatchController.watchApplies(to: document.readerStore.fileURL)
        }) else {
            return
        }

        folderWatchController.stopWatching()
    }

    func openDocumentsInApplication(_ application: ReaderExternalApplication?, documentIDs: Set<UUID>) {
        for document in orderedDocuments(matching: documentIDs) where document.readerStore.fileURL != nil {
            document.readerStore.openCurrentFileInApplication(application)
        }
    }

    func revealDocumentsInFinder(_ documentIDs: Set<UUID>) {
        for document in orderedDocuments(matching: documentIDs) where document.readerStore.fileURL != nil {
            document.readerStore.revealCurrentFileInFinder()
        }
    }

    func dismissFolderWatchAutoOpenWarnings() {
        folderWatchController.dismissFolderWatchAutoOpenWarning()
    }

    func dismissPendingFileSelectionRequest() {
        folderWatchController.pendingFileSelectionRequest = nil
        pendingFileSelectionRequest = nil
    }

    func watchedDocumentIDs() -> Set<UUID> {
        Set(documents.compactMap { document in
            folderWatchController.watchApplies(to: document.readerStore.fileURL) ? document.id : nil
        })
    }

    func document(for fileURL: URL) -> Document? {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        return documents.first(where: { document in
            guard let fileURL = document.readerStore.fileURL else {
                return false
            }

            return ReaderFileRouting.normalizedFileURL(fileURL) == normalizedFileURL
        })
    }

    private func scheduleLoadWithOverlay(on store: ReaderStore, load: @escaping @MainActor () -> Void) {
        store.transitionToLoading()
        Task { @MainActor in
            await Task.yield()
            load()
            store.holdLoadingOverlayBriefly()
        }
    }

    private func bindSelectedStore() {
        selectedStoreBindingGeneration &+= 1
        let bindingGeneration = selectedStoreBindingGeneration

        selectedStoreProjection.bind(to: selectedReaderStore) { [weak self] state in
            self?.scheduleSelectedStoreProjection(state, bindingGeneration: bindingGeneration)
        }
    }

    private func makeDocument() -> Document {
        Document(id: UUID(), readerStore: makeReaderStore())
    }

    private func synchronizeDocumentChangeObservers() {
        let currentDocumentIDs = Set(documents.map(\.id))

        for documentID in documentChangeCancellables.keys where !currentDocumentIDs.contains(documentID) {
            documentChangeCancellables[documentID] = nil
        }

        for document in documents where documentChangeCancellables[document.id] == nil {
            documentChangeCancellables[document.id] = document.readerStore.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    private func orderedDocuments(matching documentIDs: Set<UUID>) -> [Document] {
        documents.filter { documentIDs.contains($0.id) }
    }

    private func resolvedFolderWatchSession(
        for fileURL: URL,
        requestedSession: ReaderFolderWatchSession?
    ) -> ReaderFolderWatchSession? {
        if let requestedSession {
            return requestedSession
        }

        guard folderWatchController.watchApplies(to: fileURL) else {
            return nil
        }

        return activeFolderWatchSession
    }

    private func applySelectedStoreProjection(_ state: ReaderSidebarSelectedStoreProjection.State) {
        selectedWindowTitle = state.windowTitle
        selectedFileURL = state.fileURL
        selectedHasUnacknowledgedExternalChange = state.hasUnacknowledgedExternalChange
    }

    private func scheduleSelectedStoreProjection(
        _ state: ReaderSidebarSelectedStoreProjection.State,
        bindingGeneration: UInt
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  self.selectedStoreBindingGeneration == bindingGeneration else {
                return
            }

            self.applySelectedStoreProjection(state)
        }
    }

    private func configureFolderWatchController() {
        folderWatchController.currentDocumentFileURLProvider = { [weak self] in
            self?.selectedReaderStore.fileURL
        }
        folderWatchController.openDocumentFileURLsProvider = { [weak self] in
            self?.documents.compactMap { document in
                document.readerStore.isDeferredDocument ? nil : document.readerStore.fileURL
            } ?? []
        }
        folderWatchController.openEventsHandler = { [weak self] events, session, origin in
            guard let self else { return }
            let coordinator = self.fileOpenCoordinator
            let diffBaselineByURL: [URL: String] = Dictionary(
                uniqueKeysWithValues: events.compactMap { event in
                    guard let previousMarkdown = event.previousMarkdown else {
                        return nil
                    }
                    return (ReaderFileRouting.normalizedFileURL(event.fileURL), previousMarkdown)
                }
            )

            // For initial batch auto-open, the folder-watch planner sends defer
            // events and load events separately, managing materialization itself via
            // selectNewestDocumentHandler. Use .deferThenMaterializeSelected to get
            // deferOnly load mode, but suppress post-materialization (.loadAll = no-op)
            // so the planner stays in control.
            let useDeferOnly = origin == .folderWatchInitialBatchAutoOpen
            let request = FileOpenRequest(
                fileURLs: events.map(\.fileURL),
                origin: origin,
                folderWatchSession: session,
                initialDiffBaselineMarkdownByURL: diffBaselineByURL,
                slotStrategy: .reuseEmptySlotForFirst,
                materializationStrategy: useDeferOnly ? .deferThenMaterializeSelected : .loadAll
            )

            if useDeferOnly {
                let plan = coordinator.buildPlan(for: request)
                self.executePlan(FileOpenPlan(
                    assignments: plan.assignments,
                    origin: plan.origin,
                    folderWatchSession: plan.folderWatchSession,
                    materializationStrategy: .loadAll
                ))
            } else {
                coordinator.open(request)
            }
        }
        folderWatchController.selectNewestDocumentHandler = { [weak self] in
            self?.selectDocumentWithNewestModificationDate()
        }
        folderWatchController.onStateChange = { [weak self] in
            self?.synchronizeFolderWatchState()
        }
        synchronizeFolderWatchState()
    }

    private func synchronizeFolderWatchState() {
        activeFolderWatchSession = folderWatchController.activeFolderWatchSession
        selectedFolderWatchAutoOpenWarning = folderWatchController.folderWatchAutoOpenWarning
        pendingFileSelectionRequest = folderWatchController.pendingFileSelectionRequest
        isFolderWatchInitialScanInProgress = folderWatchController.isInitialMarkdownScanInProgress
        didFolderWatchInitialScanFail = folderWatchController.didInitialMarkdownScanFail
        contentScanProgress = folderWatchController.contentScanProgress
        scannedFileCount = folderWatchController.scannedFileCount
    }
}