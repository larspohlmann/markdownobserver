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
    @Published private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    @Published private(set) var isFolderWatchInitialScanInProgress: Bool
    @Published private(set) var didFolderWatchInitialScanFail: Bool

    private let makeReaderStore: () -> ReaderStore
    private let folderWatchController: ReaderFolderWatchController
    private let selectedStoreProjection = ReaderSidebarSelectedStoreProjection()
    private var storeConfigurator: ((ReaderStore) -> Void)?
    private var selectedStoreBindingGeneration: UInt = 0
    private var documentChangeCancellables: [UUID: AnyCancellable] = [:]

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
        bindSelectedStore()
    }

    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        if let existingDocument = document(for: normalizedFileURL) {
            selectDocument(existingDocument.id)
            return
        }

        let document = selectedDocument ?? documents[0]
        let effectiveFolderWatchSession = resolvedFolderWatchSession(
            for: normalizedFileURL,
            requestedSession: folderWatchSession
        )
        document.readerStore.openFile(
            at: normalizedFileURL,
            origin: origin,
            folderWatchSession: effectiveFolderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )
        selectedDocumentID = document.id
        bindSelectedStore()
    }

    func openAdditionalDocument(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil,
        preferEmptySelection: Bool = true
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        if let existingDocument = document(for: normalizedFileURL) {
            selectDocument(existingDocument.id)
            return
        }

        let targetDocument: Document
        let shouldAppendDocument: Bool
        if preferEmptySelection,
           let selectedDocument,
           selectedDocument.readerStore.fileURL == nil,
           documents.count == 1 {
            targetDocument = selectedDocument
            shouldAppendDocument = false
        } else {
            let document = makeDocument()
            if let storeConfigurator {
                storeConfigurator(document.readerStore)
            }
            targetDocument = document
            shouldAppendDocument = true
        }

        let effectiveFolderWatchSession = resolvedFolderWatchSession(
            for: normalizedFileURL,
            requestedSession: folderWatchSession
        )

        targetDocument.readerStore.openFile(
            at: normalizedFileURL,
            origin: origin,
            folderWatchSession: effectiveFolderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )

        guard targetDocument.readerStore.fileURL != nil else {
            bindSelectedStore()
            return
        }

        if shouldAppendDocument {
            documents.append(targetDocument)
            synchronizeDocumentChangeObservers()
        }

        selectedDocumentID = targetDocument.id
        bindSelectedStore()
    }

    func openDocumentsBurst(
        at fileURLs: [URL],
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdownByURL: [URL: String] = [:],
        preferEmptySelection: Bool = true
    ) {
        let plannedURLs = ReaderFileRouting.plannedOpenFileURLs(from: fileURLs)
        guard !plannedURLs.isEmpty else {
            return
        }

        for (index, fileURL) in plannedURLs.enumerated() {
            openAdditionalDocument(
                at: fileURL,
                origin: origin,
                folderWatchSession: folderWatchSession,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdownByURL[fileURL],
                preferEmptySelection: preferEmptySelection && index == 0
            )
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

    func startWatchingFolder(folderURL: URL, options: ReaderFolderWatchOptions) throws {
        try folderWatchController.startWatching(folderURL: folderURL, options: options)
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

    func watchedDocumentIDs() -> Set<UUID> {
        Set(documents.compactMap { document in
            folderWatchController.watchApplies(to: document.readerStore.fileURL) ? document.id : nil
        })
    }

    private func document(for fileURL: URL) -> Document? {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        return documents.first(where: { document in
            guard let fileURL = document.readerStore.fileURL else {
                return false
            }

            return ReaderFileRouting.normalizedFileURL(fileURL) == normalizedFileURL
        })
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
            self?.documents.compactMap { $0.readerStore.fileURL } ?? []
        }
        folderWatchController.openEventsHandler = { [weak self] events, session, origin in
            self?.openDocumentsBurst(
                at: events.map(\.fileURL),
                origin: origin,
                folderWatchSession: session,
                initialDiffBaselineMarkdownByURL: Dictionary(
                    uniqueKeysWithValues: events.compactMap { event in
                        guard let previousMarkdown = event.previousMarkdown else {
                            return nil
                        }

                        return (ReaderFileRouting.normalizedFileURL(event.fileURL), previousMarkdown)
                    }
                ),
                preferEmptySelection: true
            )
        }
        folderWatchController.onStateChange = { [weak self] in
            self?.synchronizeFolderWatchState()
        }
        synchronizeFolderWatchState()
    }

    private func synchronizeFolderWatchState() {
        activeFolderWatchSession = folderWatchController.activeFolderWatchSession
        selectedFolderWatchAutoOpenWarning = folderWatchController.folderWatchAutoOpenWarning
        isFolderWatchInitialScanInProgress = folderWatchController.isInitialMarkdownScanInProgress
        didFolderWatchInitialScanFail = folderWatchController.didInitialMarkdownScanFail
    }
}