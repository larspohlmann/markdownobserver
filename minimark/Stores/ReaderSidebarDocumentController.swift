import Foundation
import Observation

@MainActor
@Observable
final class ReaderSidebarDocumentController {
    struct Document: Identifiable, Equatable {
        let id: UUID
        let readerStore: ReaderStore
        internal(set) var normalizedFileURL: URL?

        static func == (lhs: Document, rhs: Document) -> Bool {
            lhs.id == rhs.id
        }
    }

    private(set) var documents: [Document]
    @ObservationIgnored private var documentsByNormalizedURL: [URL: UUID] = [:]
    var selectedDocumentID: UUID
    private(set) var selectedWindowTitle: String
    private(set) var selectedFileURL: URL?
    private(set) var selectedHasUnacknowledgedExternalChange: Bool
    private(set) var selectedFolderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    private(set) var isFolderWatchInitialScanInProgress: Bool
    private(set) var didFolderWatchInitialScanFail: Bool
    private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress?
    private(set) var scannedFileCount: Int?
    private(set) var rowStates: [UUID: SidebarRowState] = [:]

    private let makeReaderStore: () -> ReaderStore
    @ObservationIgnored private var _folderWatchController: ReaderFolderWatchController?
    @ObservationIgnored private let _makeFolderWatchController: () -> ReaderFolderWatchController

    private var folderWatchController: ReaderFolderWatchController {
        if let existing = _folderWatchController {
            return existing
        }
        let controller = _makeFolderWatchController()
        controller.delegate = self
        _folderWatchController = controller
        synchronizeFolderWatchState()
        return controller
    }

    private var folderWatchControllerIfCreated: ReaderFolderWatchController? {
        _folderWatchController
    }
    @ObservationIgnored private var selectedStoreObservationTask: Task<Void, Never>?
    @ObservationIgnored private var storeConfigurator: ((ReaderStore) -> Void)?
    @ObservationIgnored var onRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?
    @ObservationIgnored var onDockTileRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?
    @ObservationIgnored private var selectedStoreBindingGeneration: UInt = 0
    @ObservationIgnored private var documentObservationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var needsInitialObservationSetup = true
    @ObservationIgnored private var rowIndicatorPulseTokens: [UUID: Int] = [:]
    @ObservationIgnored lazy var fileOpenCoordinator = FileOpenCoordinator(controller: self)

    deinit {
        selectedStoreObservationTask?.cancel()
        for task in documentObservationTasks.values { task.cancel() }
    }

    init(
        settingsStore: ReaderSettingsStore,
        makeReaderStore: (() -> ReaderStore)? = nil,
        makeFolderWatchController: (() -> ReaderFolderWatchController)? = nil
    ) {
        let resolvedMakeReaderStore = makeReaderStore ?? {
            let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
            let store = ReaderStore(
                renderer: MarkdownRenderingService(),
                differ: ChangedRegionDiffer(),
                fileWatcher: FileChangeWatcher(),
                settingsStore: settingsStore,
                securityScope: SecurityScopedResourceAccess(),
                fileActions: ReaderFileActionService(),
                systemNotifier: ReaderSystemNotifier.shared,
                folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
                    minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
                ),
                settler: settler,
                requestWatchedFolderReauthorization: { folderURL in
                    MarkdownOpenPanel.pickFolder(
                        directoryURL: folderURL,
                        title: "Reauthorize Watched Folder",
                        message: "MarkdownObserver needs write access to this watched folder to save auto-opened documents.",
                        prompt: "Grant Access"
                    )
                }
            )
            return store
        }
        self.makeReaderStore = resolvedMakeReaderStore
        self._makeFolderWatchController = makeFolderWatchController ?? {
            ReaderFolderWatchController(
                folderWatcher: FolderChangeWatcher(),
                settingsStore: settingsStore,
                securityScope: SecurityScopedResourceAccess(),
                systemNotifier: ReaderSystemNotifier.shared,
                folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
                    minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
                )
            )
        }

        let initialDocument = Document(id: UUID(), readerStore: resolvedMakeReaderStore(), normalizedFileURL: nil)
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
        rebuildDocumentURLIndex()
        rebuildAllRowStates()
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
        ensureObservationSetup()
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
        ensureObservationSetup()
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

            var documentToInsert = targetDocument
            documentToInsert.normalizedFileURL = fileURL

            if shouldAppendDocument {
                documents.append(documentToInsert)
                indexDocument(documentToInsert)
                didAppendDocuments = true
            } else if let index = documents.firstIndex(where: { $0.id == targetDocument.id }) {
                unindexDocument(documents[index])
                documents[index].normalizedFileURL = documentToInsert.normalizedFileURL
                indexDocument(documents[index])
            }

            selectedDocumentID = targetDocument.id
        }

        if didAppendDocuments {
            synchronizeDocumentChangeObservers()
        }

        // In screenshot mode, override selection to a specific document by filename
        if let targetFile = ProcessInfo.processInfo.environment["MINIMARK_SCREENSHOT_SELECT_FILE"],
           let match = documents.first(where: { $0.readerStore.fileURL?.lastPathComponent == targetFile }) {
            selectedDocumentID = match.id
        }

        applyMaterializationStrategy(plan.materializationStrategy)
        bindSelectedStore()
    }

    private func applyMaterializationStrategy(_ strategy: FileOpenRequest.MaterializationStrategy) {
        switch strategy {
        case .loadAll, .deferOnly:
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

        unindexDocument(documents[index])
        documents.remove(at: index)
        synchronizeDocumentChangeObservers()

        if documents.isEmpty {
            let replacement = makeDocument()
            documents = [replacement]
            rebuildDocumentURLIndex()
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
        rebuildDocumentURLIndex()
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
        rebuildDocumentURLIndex()
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
        rebuildDocumentURLIndex()
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

    func updateFolderWatchExcludedSubdirectories(_ paths: [String]) throws {
        try folderWatchController.updateExcludedSubdirectories(paths)
    }

    func stopWatchingFolders(_ documentIDs: Set<UUID>) {
        guard let session = activeFolderWatchSession,
              let watchController = folderWatchControllerIfCreated else {
            return
        }

        let normalizedFolder = session.folderURL
        let hasWatchedDocument = documentIDs.contains { documentID in
            guard let document = documents.first(where: { $0.id == documentID }),
                  let normalizedFileURL = document.normalizedFileURL else {
                return false
            }
            return watchController.watchApplies(
                normalizedFileURL: normalizedFileURL,
                toNormalizedFolderAt: normalizedFolder,
                scope: session.options.scope
            )
        }

        guard hasWatchedDocument else { return }
        watchController.stopWatching()
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
        guard let session = activeFolderWatchSession,
              let watchController = folderWatchControllerIfCreated else {
            return []
        }

        let normalizedFolder = session.folderURL
        return Set(documents.compactMap { document in
            guard let normalizedFileURL = document.normalizedFileURL else {
                return nil
            }
            return watchController.watchApplies(
                normalizedFileURL: normalizedFileURL,
                toNormalizedFolderAt: normalizedFolder,
                scope: session.options.scope
            ) ? document.id : nil
        })
    }

    func document(for fileURL: URL) -> Document? {
        let normalized = ReaderFileRouting.normalizedFileURL(fileURL)
        guard let documentID = documentsByNormalizedURL[normalized] else {
            return nil
        }
        return documents.first(where: { $0.id == documentID })
    }

    private func scheduleLoadWithOverlay(on store: ReaderStore, load: @escaping @MainActor () -> Void) {
        store.transitionToLoading()
        Task { @MainActor in
            await Task.yield()
            load()
            store.holdLoadingOverlayBriefly()
        }
    }

    private func ensureObservationSetup() {
        guard needsInitialObservationSetup else { return }
        needsInitialObservationSetup = false
        synchronizeDocumentChangeObservers()
        bindSelectedStore()
    }

    private func bindSelectedStore() {
        selectedStoreBindingGeneration &+= 1
        let bindingGeneration = selectedStoreBindingGeneration
        let store = selectedReaderStore

        selectedWindowTitle = store.windowTitle
        selectedFileURL = store.fileURL
        selectedHasUnacknowledgedExternalChange = store.hasUnacknowledgedExternalChange

        selectedStoreObservationTask?.cancel()
        selectedStoreObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                let cancelled = await Self.awaitObservationChange {
                    _ = store.windowTitle
                    _ = store.fileURL
                    _ = store.hasUnacknowledgedExternalChange
                }
                if cancelled { break }
                guard let self,
                      self.selectedStoreBindingGeneration == bindingGeneration else { break }
                self.selectedWindowTitle = store.windowTitle
                self.selectedFileURL = store.fileURL
                self.selectedHasUnacknowledgedExternalChange = store.hasUnacknowledgedExternalChange
            }
        }
    }

    private func makeDocument() -> Document {
        Document(id: UUID(), readerStore: makeReaderStore(), normalizedFileURL: nil)
    }

    private func rebuildDocumentURLIndex() {
        documentsByNormalizedURL = [:]
        for document in documents {
            if let normalizedURL = document.normalizedFileURL {
                documentsByNormalizedURL[normalizedURL] = document.id
            }
        }
    }

    private func indexDocument(_ document: Document) {
        if let normalizedURL = document.normalizedFileURL {
            documentsByNormalizedURL[normalizedURL] = document.id
        }
    }

    private func unindexDocument(_ document: Document) {
        if let normalizedURL = document.normalizedFileURL {
            documentsByNormalizedURL.removeValue(forKey: normalizedURL)
        }
    }

    private func deriveIndicatorState(from store: ReaderStore) -> ReaderDocumentIndicatorState {
        ReaderDocumentIndicatorState(
            hasUnacknowledgedExternalChange: store.hasUnacknowledgedExternalChange,
            isCurrentFileMissing: store.isCurrentFileMissing,
            unacknowledgedExternalChangeKind: store.content.unacknowledgedExternalChangeKind
        )
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
            indicatorPulseToken: rowIndicatorPulseTokens[document.id] ?? 0
        )
    }

    private func rebuildAllRowStates() {
        var states: [UUID: SidebarRowState] = [:]
        for document in documents {
            let previousIndicatorState = rowStates[document.id]?.indicatorState
            let currentIndicatorState = deriveIndicatorState(from: document.readerStore)
            if let previousIndicatorState,
               previousIndicatorState != currentIndicatorState,
               currentIndicatorState.showsIndicator {
                rowIndicatorPulseTokens[document.id, default: 0] += 1
            }
            states[document.id] = deriveRowState(from: document)
        }
        rowIndicatorPulseTokens = rowIndicatorPulseTokens.filter { states[$0.key] != nil }
        guard states != rowStates else { return }
        rowStates = states
        onRowStatesChanged?(states)
        onDockTileRowStatesChanged?(states)
    }

    private func synchronizeDocumentChangeObservers() {
        let currentDocumentIDs = Set(documents.map(\.id))

        for documentID in documentObservationTasks.keys where !currentDocumentIDs.contains(documentID) {
            documentObservationTasks[documentID]?.cancel()
            documentObservationTasks[documentID] = nil
        }

        for document in documents where documentObservationTasks[document.id] == nil {
            let documentID = document.id
            document.readerStore.onExternalChangeKindChanged = { [weak self] in
                self?.updateRowStateIfNeeded(for: documentID)
            }
            documentObservationTasks[document.id] = Task { [weak self] in
                let store = document.readerStore
                defer { store.onExternalChangeKindChanged = nil }
                while !Task.isCancelled {
                    let cancelled = await Self.awaitObservationChange {
                        _ = store.fileDisplayName
                        _ = store.fileLastModifiedAt
                        _ = store.lastExternalChangeAt
                        _ = store.lastRefreshAt
                        _ = store.isCurrentFileMissing
                        _ = store.hasUnacknowledgedExternalChange
                    }
                    if cancelled { break }
                    self?.updateRowStateIfNeeded(for: document.id)
                }
            }
        }

        rebuildAllRowStates()
    }

    private func updateRowStateIfNeeded(for documentID: UUID) {
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        let previousIndicatorState = rowStates[documentID]?.indicatorState
        let currentIndicatorState = deriveIndicatorState(from: document.readerStore)
        if let previousIndicatorState,
           previousIndicatorState != currentIndicatorState,
           currentIndicatorState.showsIndicator {
            rowIndicatorPulseTokens[documentID, default: 0] += 1
        }
        let state = deriveRowState(from: document)
        if rowStates[documentID] != state {
            rowStates[documentID] = state
            onRowStatesChanged?(rowStates)
            onDockTileRowStatesChanged?(rowStates)
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

        guard let watchController = folderWatchControllerIfCreated,
              watchController.watchApplies(to: fileURL) else {
            return nil
        }

        return activeFolderWatchSession
    }


    // MARK: - Observation helpers

    /// Suspends until any property accessed inside `tracking` changes, or the enclosing Task is cancelled.
    /// Returns `true` if the wait was terminated by cancellation rather than a property change.
    private static func awaitObservationChange(
        tracking: @escaping @MainActor () -> Void
    ) async -> Bool {
        let box = ObservationContinuationBox()
        return await withTaskCancellationHandler {
            await withUnsafeContinuation { continuation in
                box.store(continuation)
                if Task.isCancelled {
                    box.resume(returning: true)
                    return
                }
                withObservationTracking {
                    tracking()
                } onChange: {
                    box.resume(returning: false)
                }
            }
        } onCancel: {
            box.resume(returning: true)
        }
    }

    private final class ObservationContinuationBox: @unchecked Sendable {
        private var continuation: UnsafeContinuation<Bool, Never>?
        private let lock = NSLock()

        func store(_ continuation: UnsafeContinuation<Bool, Never>) {
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }

        func resume(returning value: Bool) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    private func synchronizeFolderWatchState() {
        guard let controller = _folderWatchController else {
            activeFolderWatchSession = nil
            selectedFolderWatchAutoOpenWarning = nil
            pendingFileSelectionRequest = nil
            isFolderWatchInitialScanInProgress = false
            didFolderWatchInitialScanFail = false
            contentScanProgress = nil
            scannedFileCount = nil
            return
        }
        activeFolderWatchSession = controller.activeFolderWatchSession
        selectedFolderWatchAutoOpenWarning = controller.folderWatchAutoOpenWarning
        pendingFileSelectionRequest = controller.pendingFileSelectionRequest
        isFolderWatchInitialScanInProgress = controller.isInitialMarkdownScanInProgress
        didFolderWatchInitialScanFail = controller.didInitialMarkdownScanFail
        contentScanProgress = controller.contentScanProgress
        scannedFileCount = controller.scannedFileCount
    }
}

extension ReaderSidebarDocumentController: ReaderFolderWatchControllerDelegate {
    func folderWatchControllerCurrentDocumentFileURL(_ controller: ReaderFolderWatchController) -> URL? {
        selectedReaderStore.fileURL
    }

    func folderWatchControllerOpenDocumentFileURLs(_ controller: ReaderFolderWatchController) -> [URL] {
        documents.compactMap { document in
            document.readerStore.isDeferredDocument ? nil : document.readerStore.fileURL
        }
    }

    func folderWatchController(
        _ controller: ReaderFolderWatchController,
        handleEvents events: [ReaderFolderWatchChangeEvent],
        in session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        let coordinator = fileOpenCoordinator
        let diffBaselineByURL: [URL: String] = Dictionary(
            uniqueKeysWithValues: events.compactMap { event in
                guard let previousMarkdown = event.previousMarkdown else {
                    return nil
                }
                return (ReaderFileRouting.normalizedFileURL(event.fileURL), previousMarkdown)
            }
        )

        // For initial batch auto-open, the folder-watch planner sends defer
        // and load events separately, managing materialization itself via
        // folderWatchControllerShouldSelectNewestDocument. Use .deferOnly so the planner stays in control.
        let materializationStrategy: FileOpenRequest.MaterializationStrategy =
            origin == .folderWatchInitialBatchAutoOpen ? .deferOnly : .loadAll

        coordinator.open(FileOpenRequest(
            fileURLs: events.map(\.fileURL),
            origin: origin,
            folderWatchSession: session,
            initialDiffBaselineMarkdownByURL: diffBaselineByURL,
            slotStrategy: .reuseEmptySlotForFirst,
            materializationStrategy: materializationStrategy
        ))
    }

    func folderWatchController(_ controller: ReaderFolderWatchController, didLiveAutoOpenFileURLs urls: [URL]) {
        for url in urls {
            if let doc = document(for: url) {
                doc.readerStore.noteObservedExternalChange(kind: .added)
            }
        }
    }

    func folderWatchControllerShouldSelectNewestDocument(_ controller: ReaderFolderWatchController) {
        selectDocumentWithNewestModificationDate()
    }

    func folderWatchControllerStateDidChange(_ controller: ReaderFolderWatchController) {
        synchronizeFolderWatchState()
    }
}
