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

    // MARK: - Extracted components

    @ObservationIgnored private let documentList: SidebarDocumentList
    @ObservationIgnored private let rowStateComputer = SidebarRowStateComputer()
    @ObservationIgnored private let observationManager = SidebarObservationManager()
    let folderWatchCoordinator: FolderWatchSessionCoordinator
    @ObservationIgnored private let fileOpenPlanExecutor: FileOpenPlanExecutor

    // MARK: - Selection state

    var selectedDocumentID: UUID
    private(set) var selectedWindowTitle: String
    private(set) var selectedFileURL: URL?
    private(set) var selectedHasUnacknowledgedExternalChange: Bool

    // MARK: - Dependencies

    private let makeReaderStore: () -> ReaderStore
    @ObservationIgnored private(set) var storeConfigurator: ((ReaderStore) -> Void)?
    @ObservationIgnored lazy var fileOpenCoordinator = FileOpenCoordinator(controller: self)

    // MARK: - Forwarding API

    var documents: [Document] { documentList.documents }
    var rowStates: [UUID: SidebarRowState] { rowStateComputer.rowStates }

    @ObservationIgnored var onRowStatesChanged: (([UUID: SidebarRowState]) -> Void)? {
        get { rowStateComputer.onRowStatesChanged }
        set { rowStateComputer.onRowStatesChanged = newValue }
    }

    @ObservationIgnored var onDockTileRowStatesChanged: (([UUID: SidebarRowState]) -> Void)? {
        get { rowStateComputer.onDockTileRowStatesChanged }
        set { rowStateComputer.onDockTileRowStatesChanged = newValue }
    }

    func deriveRowState(from document: Document) -> SidebarRowState {
        rowStateComputer.deriveRowState(from: document)
    }

    func document(for fileURL: URL) -> Document? {
        documentList.document(for: fileURL)
    }

    // MARK: - Init

    init(
        settingsStore: ReaderSettingsStore,
        makeReaderStore: (() -> ReaderStore)? = nil,
        makeFolderWatchController: (() -> ReaderFolderWatchController)? = nil
    ) {
        let resolvedMakeReaderStore = makeReaderStore ?? {
            let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
            let securityScopeResolver = SecurityScopeResolver(
                securityScope: SecurityScopedResourceAccess(),
                settingsStore: settingsStore,
                requestWatchedFolderReauthorization: { folderURL in
                    MarkdownOpenPanel.pickFolder(
                        directoryURL: folderURL,
                        title: "Reauthorize Watched Folder",
                        message: "MarkdownObserver needs write access to this watched folder to save auto-opened documents.",
                        prompt: "Grant Access"
                    )
                }
            )
            let store = ReaderStore(
                rendering: ReaderRenderingDependencies(
                    renderer: MarkdownRenderingService(),
                    differ: ChangedRegionDiffer()
                ),
                file: ReaderFileDependencies(
                    watcher: FileChangeWatcher(),
                    io: ReaderDocumentIOService(),
                    actions: ReaderFileActionService()
                ),
                folderWatch: ReaderFolderWatchDependencies(
                    autoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
                        minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
                    ),
                    settler: settler,
                    systemNotifier: ReaderSystemNotifier.shared
                ),
                settingsStore: settingsStore,
                securityScopeResolver: securityScopeResolver
            )
            return store
        }
        self.makeReaderStore = resolvedMakeReaderStore
        let resolvedMakeFolderWatchController = makeFolderWatchController ?? {
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
        folderWatchCoordinator = FolderWatchSessionCoordinator(
            makeFolderWatchController: resolvedMakeFolderWatchController
        )

        let initialDocument = Document(id: UUID(), readerStore: resolvedMakeReaderStore(), normalizedFileURL: nil)
        documentList = SidebarDocumentList(initialDocument: initialDocument)
        fileOpenPlanExecutor = FileOpenPlanExecutor(
            documentList: documentList,
            observationManager: observationManager,
            rowStateComputer: rowStateComputer
        )
        selectedDocumentID = initialDocument.id
        selectedWindowTitle = initialDocument.readerStore.windowTitle
        selectedFileURL = initialDocument.readerStore.fileURL
        selectedHasUnacknowledgedExternalChange = initialDocument.readerStore.hasUnacknowledgedExternalChange
        rowStateComputer.rebuildAllRowStates(from: documentList.documents)
        folderWatchCoordinator.delegate = self
        fileOpenPlanExecutor.delegate = self
    }

    // MARK: - Selection

    var selectedDocument: Document? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    var selectedReaderStore: ReaderStore {
        selectedDocument?.readerStore ?? documents[0].readerStore
    }

    func setStoreConfigurator(_ configurator: @escaping (ReaderStore) -> Void) {
        storeConfigurator = configurator
        for document in documents {
            configurator(document.readerStore)
        }
    }

    func selectDocument(_ documentID: UUID?) {
        observationManager.ensureSetup(for: documents, onStoreChanged: makeStoreChangedHandler())
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
        fileOpenPlanExecutor.selectDocumentWithNewestModificationDate()
    }

    func materializeNewestDeferredDocuments(
        count: Int = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    ) {
        fileOpenPlanExecutor.materializeNewestDeferredDocuments(count: count)
    }

    // MARK: - Plan execution

    func executePlan(_ plan: FileOpenPlan) {
        fileOpenPlanExecutor.executePlan(plan)
    }

    // MARK: - Document close

    func closeDocument(_ documentID: UUID) {
        guard let removed = documentList.remove(documentID: documentID) else {
            return
        }

        if documents.isEmpty {
            let replacement = makeDocument()
            documentList.replaceAll(with: [replacement])
            if let storeConfigurator {
                storeConfigurator(replacement.readerStore)
            }
            selectedDocumentID = replacement.id
            synchronizeAndRebuild()
            bindSelectedStore()
            return
        }

        if selectedDocumentID == documentID {
            let nextIndex = min(removed.index, documents.count - 1)
            selectedDocumentID = documents[nextIndex].id
        }

        synchronizeAndRebuild()
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

        documentList.replaceAll(with: retainedDocuments)

        if !retainedDocuments.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = retainedDocuments[0].id
        }

        synchronizeAndRebuild()
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
        documentList.replaceAll(with: remainingDocuments)

        if !remainingDocuments.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = remainingDocuments[0].id
        }

        synchronizeAndRebuild()
        bindSelectedStore()
    }

    func closeAllDocuments() {
        let replacement = makeDocument()
        if let storeConfigurator {
            storeConfigurator(replacement.readerStore)
        }

        documentList.replaceAll(with: [replacement])
        selectedDocumentID = replacement.id
        synchronizeAndRebuild()
        bindSelectedStore()
    }

    // MARK: - Document actions

    func openDocumentsInApplication(_ application: ReaderExternalApplication?, documentIDs: Set<UUID>) {
        for document in documentList.orderedDocuments(matching: documentIDs) where document.readerStore.fileURL != nil {
            document.readerStore.openCurrentFileInApplication(application)
        }
    }

    func revealDocumentsInFinder(_ documentIDs: Set<UUID>) {
        for document in documentList.orderedDocuments(matching: documentIDs) where document.readerStore.fileURL != nil {
            document.readerStore.revealCurrentFileInFinder()
        }
    }

    // MARK: - Internal helpers

    func makeDocument() -> Document {
        Document(id: UUID(), readerStore: makeReaderStore(), normalizedFileURL: nil)
    }

    private func scheduleLoadWithOverlay(on store: ReaderStore, load: @escaping @MainActor () -> Void) {
        store.transitionToLoading()
        Task { @MainActor in
            await Task.yield()
            load()
            store.holdLoadingOverlayBriefly()
        }
    }

    func bindSelectedStore() {
        let store = selectedReaderStore
        selectedWindowTitle = store.windowTitle
        selectedFileURL = store.fileURL
        selectedHasUnacknowledgedExternalChange = store.hasUnacknowledgedExternalChange

        observationManager.bindSelectedStore(store) { [weak self] in
            guard let self else { return }
            self.selectedWindowTitle = store.windowTitle
            self.selectedFileURL = store.fileURL
            self.selectedHasUnacknowledgedExternalChange = store.hasUnacknowledgedExternalChange
        }
    }

    private func synchronizeAndRebuild() {
        observationManager.synchronize(for: documents, onStoreChanged: makeStoreChangedHandler())
        rowStateComputer.rebuildAllRowStates(from: documents)
    }

    private func makeStoreChangedHandler() -> @MainActor (UUID) -> Void {
        return { [weak self] documentID in
            guard let self else { return }
            self.rowStateComputer.updateRowStateIfNeeded(for: documentID, in: self.documents)
        }
    }

}

// MARK: - FolderWatchSessionCoordinatorDelegate

extension ReaderSidebarDocumentController: FolderWatchSessionCoordinatorDelegate {
    func handleFolderWatchOpenRequest(_ request: FileOpenRequest) {
        fileOpenCoordinator.open(request)
    }
}

// MARK: - FileOpenPlanExecutorDelegate

extension ReaderSidebarDocumentController: FileOpenPlanExecutorDelegate {
    func resolvedFolderWatchSession(
        for fileURL: URL,
        requestedSession: ReaderFolderWatchSession?
    ) -> ReaderFolderWatchSession? {
        folderWatchCoordinator.resolvedFolderWatchSession(
            for: fileURL,
            requestedSession: requestedSession
        )
    }
}
