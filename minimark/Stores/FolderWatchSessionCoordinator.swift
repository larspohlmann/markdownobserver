import Foundation
import Observation

@MainActor
protocol FolderWatchSessionCoordinatorDelegate: AnyObject {
    typealias Document = ReaderSidebarDocumentController.Document

    var documents: [Document] { get }
    var selectedReaderStore: ReaderStore { get }
    func document(for fileURL: URL) -> Document?
    func selectDocumentWithNewestModificationDate()
    func handleFolderWatchOpenRequest(_ request: FileOpenRequest)
}

@MainActor
@Observable
final class FolderWatchSessionCoordinator {
    typealias Document = ReaderSidebarDocumentController.Document

    // MARK: - State

    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    private(set) var selectedFolderWatchAutoOpenWarning: FolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?
    private(set) var isFolderWatchInitialScanInProgress: Bool
    private(set) var didFolderWatchInitialScanFail: Bool
    private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress?
    private(set) var scannedFileCount: Int?

    var canStopFolderWatch: Bool {
        activeFolderWatchSession != nil
    }

    // MARK: - Dependencies

    @ObservationIgnored private var _folderWatchController: FolderWatchController?
    @ObservationIgnored private let _makeFolderWatchController: () -> FolderWatchController
    @ObservationIgnored weak var delegate: FolderWatchSessionCoordinatorDelegate?

    // MARK: - Lazy controller access

    private var folderWatchController: FolderWatchController {
        if let existing = _folderWatchController {
            return existing
        }
        let controller = _makeFolderWatchController()
        controller.delegate = self
        _folderWatchController = controller
        synchronizeFolderWatchState()
        return controller
    }

    var folderWatchControllerIfCreated: FolderWatchController? {
        _folderWatchController
    }

    // MARK: - Init

    init(makeFolderWatchController: @escaping () -> FolderWatchController) {
        self._makeFolderWatchController = makeFolderWatchController
        self.activeFolderWatchSession = nil
        self.selectedFolderWatchAutoOpenWarning = nil
        self.pendingFileSelectionRequest = nil
        self.isFolderWatchInitialScanInProgress = false
        self.didFolderWatchInitialScanFail = false
        self.contentScanProgress = nil
        self.scannedFileCount = nil
    }

    // MARK: - Pass-through methods

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

    func dismissFolderWatchAutoOpenWarnings() {
        folderWatchController.dismissFolderWatchAutoOpenWarning()
    }

    func dismissPendingFileSelectionRequest() {
        folderWatchController.pendingFileSelectionRequest = nil
        pendingFileSelectionRequest = nil
    }

    // MARK: - Methods with real logic

    func stopWatchingFolders(_ documentIDs: Set<UUID>) {
        guard let session = activeFolderWatchSession,
              let watchController = folderWatchControllerIfCreated else {
            return
        }

        let normalizedFolder = session.folderURL
        let hasWatchedDocument = documentIDs.contains { documentID in
            guard let delegate,
                  let document = delegate.documents.first(where: { $0.id == documentID }),
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

    func watchedDocumentIDs() -> Set<UUID> {
        guard let session = activeFolderWatchSession,
              let watchController = folderWatchControllerIfCreated,
              let delegate else {
            return []
        }

        let normalizedFolder = session.folderURL
        return Set(delegate.documents.compactMap { document in
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

    func resolvedFolderWatchSession(
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

    // MARK: - Private

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

// MARK: - FolderWatchControllerDelegate

extension FolderWatchSessionCoordinator: FolderWatchControllerDelegate {
    func folderWatchControllerCurrentDocumentFileURL(_ controller: FolderWatchController) -> URL? {
        delegate?.selectedReaderStore.document.fileURL
    }

    func folderWatchControllerOpenDocumentFileURLs(_ controller: FolderWatchController) -> [URL] {
        guard let delegate else { return [] }
        return delegate.documents.compactMap { document in
            document.readerStore.document.isDeferredDocument ? nil : document.readerStore.document.fileURL
        }
    }

    func folderWatchController(
        _ controller: FolderWatchController,
        handleEvents events: [ReaderFolderWatchChangeEvent],
        in session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        let diffBaselineByURL: [URL: String] = Dictionary(
            uniqueKeysWithValues: events.compactMap { event in
                guard let previousMarkdown = event.previousMarkdown else {
                    return nil
                }
                return (ReaderFileRouting.normalizedFileURL(event.fileURL), previousMarkdown)
            }
        )

        let materializationStrategy: FileOpenRequest.MaterializationStrategy =
            origin == .folderWatchInitialBatchAutoOpen ? .deferOnly : .loadAll

        delegate?.handleFolderWatchOpenRequest(FileOpenRequest(
            fileURLs: events.map(\.fileURL),
            origin: origin,
            folderWatchSession: session,
            initialDiffBaselineMarkdownByURL: diffBaselineByURL,
            slotStrategy: .reuseEmptySlotForFirst,
            materializationStrategy: materializationStrategy
        ))
    }

    func folderWatchController(_ controller: FolderWatchController, didLiveAutoOpenFileURLs urls: [URL]) {
        guard let delegate else { return }
        for url in urls {
            if let doc = delegate.document(for: url) {
                doc.readerStore.markAsLiveAutoOpened()
            }
        }
    }

    func folderWatchControllerShouldSelectNewestDocument(_ controller: FolderWatchController) {
        delegate?.selectDocumentWithNewestModificationDate()
    }

    func folderWatchControllerStateDidChange(_ controller: FolderWatchController) {
        synchronizeFolderWatchState()
    }
}
