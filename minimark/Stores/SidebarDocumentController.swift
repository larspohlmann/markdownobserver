import Foundation
import Observation

@MainActor
@Observable
final class SidebarDocumentController {
    struct Document: Identifiable, Equatable {
        let id: UUID
        let readerStore: DocumentStore
        var normalizedFileURL: URL?

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
    @ObservationIgnored private let documentCloseCoordinator: DocumentCloseCoordinator

    // MARK: - Selection state

    var selectedDocumentID: UUID
    private(set) var selectedWindowTitle: String
    private(set) var selectedFileURL: URL?
    private(set) var selectedHasUnacknowledgedExternalChange: Bool

    // MARK: - Dependencies

    private let makeReaderStore: () -> DocumentStore
    @ObservationIgnored private(set) var storeConfigurator: ((DocumentStore) -> Void)?
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
        settingsStore: SettingsStore,
        makeReaderStore: (() -> DocumentStore)? = nil,
        makeFolderWatchController: (() -> FolderWatchController)? = nil
    ) {
        let resolvedMakeReaderStore = makeReaderStore ?? {
            let settler = AutoOpenSettler(settlingInterval: 1.0)
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
            let store = DocumentStore(
                rendering: RenderingDependencies(
                    renderer: MarkdownRenderingService(),
                    differ: ChangedRegionDiffer()
                ),
                file: FileDependencies(
                    watcher: FileChangeWatcher(),
                    io: DocumentIOService(),
                    actions: FileActionService()
                ),
                folderWatch: FolderWatchDependencies(
                    autoOpenPlanner: FolderWatchAutoOpenPlanner(
                        minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
                    ),
                    settler: settler,
                    systemNotifier: SystemNotifier.shared
                ),
                settingsStore: settingsStore,
                securityScopeResolver: securityScopeResolver
            )
            return store
        }
        self.makeReaderStore = resolvedMakeReaderStore
        let resolvedMakeFolderWatchController = makeFolderWatchController ?? {
            FolderWatchController(
                folderWatcher: FolderChangeWatcher(),
                settingsStore: settingsStore,
                securityScope: SecurityScopedResourceAccess(),
                systemNotifier: SystemNotifier.shared,
                folderWatchAutoOpenPlanner: FolderWatchAutoOpenPlanner(
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
        documentCloseCoordinator = DocumentCloseCoordinator(
            documentList: documentList,
            observationManager: observationManager,
            rowStateComputer: rowStateComputer
        )
        selectedDocumentID = initialDocument.id
        selectedWindowTitle = initialDocument.readerStore.document.windowTitle
        selectedFileURL = initialDocument.readerStore.document.fileURL
        selectedHasUnacknowledgedExternalChange = initialDocument.readerStore.externalChange.hasUnacknowledgedExternalChange
        rowStateComputer.rebuildAllRowStates(from: documentList.documents)
        folderWatchCoordinator.delegate = self
        fileOpenPlanExecutor.delegate = self
        documentCloseCoordinator.delegate = self
    }

    // MARK: - Selection

    var selectedDocument: Document? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    var selectedReaderStore: DocumentStore {
        selectedDocument?.readerStore ?? documents[0].readerStore
    }

    func setStoreConfigurator(_ configurator: @escaping (DocumentStore) -> Void) {
        storeConfigurator = configurator
        for document in documents {
            configurator(document.readerStore)
        }
    }

    func selectDocument(_ documentID: UUID?) {
        observationManager.ensureSetup(for: documents) { [weak self] documentID in
            guard let self else { return }
            self.rowStateComputer.updateRowStateIfNeeded(for: documentID, in: self.documents)
        }
        guard let documentID,
              documents.contains(where: { $0.id == documentID }) else {
            return
        }

        if selectedDocumentID == documentID {
            // Re-selecting the same document is a no-op UNLESS the store is still
            // deferred — in that case we must materialize (see #345). Avoid
            // reassigning `selectedDocumentID` so Observation doesn't fire for a
            // ready-state reselect.
            let store = selectedReaderStore
            guard store.document.isDeferredDocument else { return }
            scheduleLoadWithOverlay(on: store) {
                store.opener.materializeDeferred()
            }
            return
        }

        selectedDocumentID = documentID
        let store = selectedReaderStore

        if store.document.isDeferredDocument {
            scheduleLoadWithOverlay(on: store) {
                store.opener.materializeDeferred()
            }
        }
        bindSelectedStore()
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
        count: Int = FolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    ) {
        fileOpenPlanExecutor.materializeNewestDeferredDocuments(count: count)
    }

    // MARK: - Plan execution

    func executePlan(_ plan: FileOpenPlan) {
        fileOpenPlanExecutor.executePlan(plan)
    }

    // MARK: - Document close

    func closeDocument(_ documentID: UUID) {
        documentCloseCoordinator.closeDocument(documentID)
    }

    func closeOtherDocuments(keeping documentID: UUID) {
        documentCloseCoordinator.closeOtherDocuments(keeping: documentID)
    }

    func closeOtherDocuments(keeping documentIDs: Set<UUID>) {
        documentCloseCoordinator.closeOtherDocuments(keeping: documentIDs)
    }

    func closeDocuments(_ documentIDs: Set<UUID>) {
        documentCloseCoordinator.closeDocuments(documentIDs)
    }

    func closeAllDocuments() {
        documentCloseCoordinator.closeAllDocuments()
    }

    // MARK: - Document actions

    func openDocumentsInApplication(_ application: ExternalApplication?, documentIDs: Set<UUID>) {
        for tab in documentList.orderedDocuments(matching: documentIDs) where tab.readerStore.document.fileURL != nil {
            tab.readerStore.document.openInApplication(application)
        }
    }

    func revealDocumentsInFinder(_ documentIDs: Set<UUID>) {
        for tab in documentList.orderedDocuments(matching: documentIDs) where tab.readerStore.document.fileURL != nil {
            tab.readerStore.document.revealInFinder()
        }
    }

    // MARK: - Internal helpers

    func makeDocument() -> Document {
        Document(id: UUID(), readerStore: makeReaderStore(), normalizedFileURL: nil)
    }

    private func scheduleLoadWithOverlay(on store: DocumentStore, load: @escaping @MainActor () -> Void) {
        store.document.transitionToLoading()
        Task { @MainActor in
            await Task.yield()
            load()
            store.document.holdLoadingOverlayBriefly()
        }
    }

    func bindSelectedStore() {
        let store = selectedReaderStore
        selectedWindowTitle = store.document.windowTitle
        selectedFileURL = store.document.fileURL
        selectedHasUnacknowledgedExternalChange = store.externalChange.hasUnacknowledgedExternalChange

        observationManager.bindSelectedStore(store) { [weak self] in
            guard let self else { return }
            self.selectedWindowTitle = store.document.windowTitle
            self.selectedFileURL = store.document.fileURL
            self.selectedHasUnacknowledgedExternalChange = store.externalChange.hasUnacknowledgedExternalChange
        }
    }

}

// MARK: - Delegate conformances

extension SidebarDocumentController: FolderWatchSessionCoordinatorDelegate {
    func handleFolderWatchOpenRequest(_ request: FileOpenRequest) {
        fileOpenCoordinator.open(request)
    }
}

extension SidebarDocumentController: FileOpenPlanExecutorDelegate {
    func resolvedFolderWatchSession(
        for fileURL: URL,
        requestedSession: FolderWatchSession?
    ) -> FolderWatchSession? {
        folderWatchCoordinator.resolvedFolderWatchSession(
            for: fileURL,
            requestedSession: requestedSession
        )
    }
}

extension SidebarDocumentController: DocumentCloseCoordinatorDelegate {}
