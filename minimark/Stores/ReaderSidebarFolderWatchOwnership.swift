import Foundation

enum FolderWatchUpdateError: Error, LocalizedError {
    case noActiveWatch

    var errorDescription: String? {
        switch self {
        case .noActiveWatch:
            return "No folder is currently being watched."
        }
    }
}

@MainActor
final class ReaderFolderWatchController {
    private static let scanProgressLingerDuration: Duration = .milliseconds(500)

    private let folderWatcher: FolderChangeWatching
    private let settingsStore: ReaderSettingsStoring
    private let securityScope: SecurityScopedResourceAccessing
    private let systemNotifier: ReaderSystemNotifying
    private let folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning

    private var folderSecurityScopeToken: SecurityScopedAccessToken?
    private var initialMarkdownScanTask: Task<Void, Never>?
    private var scanProgressTask: Task<Void, Never>?

    weak var delegate: ReaderFolderWatchControllerDelegate?

    private(set) var activeFolderWatchSession: ReaderFolderWatchSession? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var lastWatchedFolderEventAt: Date? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var isInitialMarkdownScanInProgress = false {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var didInitialMarkdownScanFail = false {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    private(set) var scannedFileCount: Int? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest? {
        didSet { delegate?.folderWatchControllerStateDidChange(self) }
    }

    init(
        folderWatcher: FolderChangeWatching,
        settingsStore: ReaderSettingsStoring,
        securityScope: SecurityScopedResourceAccessing,
        systemNotifier: ReaderSystemNotifying,
        folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning
    ) {
        self.folderWatcher = folderWatcher
        self.settingsStore = settingsStore
        self.securityScope = securityScope
        self.systemNotifier = systemNotifier
        self.folderWatchAutoOpenPlanner = folderWatchAutoOpenPlanner
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    func startWatching(
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        performInitialAutoOpen: Bool = true
    ) throws {
        stopWatching()
        folderWatchAutoOpenWarning = nil
        pendingFileSelectionRequest = nil
        folderWatchAutoOpenPlanner.resetTransientState()
        folderWatchAutoOpenPlanner.updateMinimumDiffBaselineAge(
            settingsStore.currentSettings.diffBaselineLookback.timeInterval
        )
        didInitialMarkdownScanFail = false

        let accessibleFolderURL = folderURL
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(accessibleFolderURL)
        let excludedSubdirectoryURLs = options.resolvedExcludedSubdirectoryURLs(relativeTo: normalizedFolderURL)
        folderSecurityScopeToken = securityScope.beginAccess(to: accessibleFolderURL)

        do {
            try folderWatcher.startWatching(
                folderURL: accessibleFolderURL,
                includeSubfolders: options.scope == .includeSubfolders,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            ) { [weak self] changedMarkdownEvents in
                guard let self else {
                    return
                }

                Task { @MainActor [self] in
                    self.handleObservedWatchedFolderChanges(changedMarkdownEvents)
                }
            }

            let session = ReaderFolderWatchSession(
                folderURL: normalizedFolderURL,
                options: options,
                startedAt: .now
            )
            activeFolderWatchSession = session
            settingsStore.addRecentWatchedFolder(accessibleFolderURL, options: options)
            lastWatchedFolderEventAt = nil

            let isAutoOpenPath = performInitialAutoOpen && options.openMode == .openAllMarkdownFiles
            isInitialMarkdownScanInProgress = true

            let progressStream = folderWatcher.scanProgressStream
            scanProgressTask?.cancel()
            scanProgressTask = Task { [weak self] in
                var lastProgress: FolderChangeWatcher.ScanProgress?
                for await progress in progressStream {
                    guard !Task.isCancelled else { return }
                    self?.contentScanProgress = progress
                    lastProgress = progress
                }
                guard !Task.isCancelled else { return }
                if let lastProgress {
                    self?.scannedFileCount = lastProgress.total
                }
                if !isAutoOpenPath {
                    self?.isInitialMarkdownScanInProgress = false
                }
                try? await Task.sleep(for: Self.scanProgressLingerDuration)
                guard !Task.isCancelled else { return }
                self?.contentScanProgress = nil
            }

            guard isAutoOpenPath else {
                return
            }

            if options.scope == .includeSubfolders {
                loadInitialMarkdownFilesOffMainActor(
                    for: session,
                    folderURL: accessibleFolderURL,
                    includeSubfolders: true,
                    excludedSubdirectoryURLs: excludedSubdirectoryURLs
                )
            } else {
                let markdownURLs = try folderWatcher.markdownFiles(
                    in: accessibleFolderURL,
                    includeSubfolders: false,
                    excludedSubdirectoryURLs: excludedSubdirectoryURLs
                )
                applyInitialAutoOpenMarkdownURLs(markdownURLs, for: session)
            }
        } catch {
            scanProgressTask?.cancel()
            scanProgressTask = nil
            folderWatcher.stopWatching()
            folderSecurityScopeToken?.endAccess()
            folderSecurityScopeToken = nil
            activeFolderWatchSession = nil
            lastWatchedFolderEventAt = nil
            folderWatchAutoOpenWarning = nil
            isInitialMarkdownScanInProgress = false
            didInitialMarkdownScanFail = false
            contentScanProgress = nil
            throw error
        }
    }

    func stopWatching() {
        initialMarkdownScanTask?.cancel()
        initialMarkdownScanTask = nil
        scanProgressTask?.cancel()
        scanProgressTask = nil
        folderWatcher.stopWatching()
        folderWatchAutoOpenPlanner.resetTransientState()
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = nil
        activeFolderWatchSession = nil
        lastWatchedFolderEventAt = nil
        folderWatchAutoOpenWarning = nil
        pendingFileSelectionRequest = nil
        isInitialMarkdownScanInProgress = false
        didInitialMarkdownScanFail = false
        contentScanProgress = nil
        scannedFileCount = nil
    }

    func updateExcludedSubdirectories(_ paths: [String]) throws {
        guard let session = activeFolderWatchSession else {
            throw FolderWatchUpdateError.noActiveWatch
        }

        let updatedOptions = ReaderFolderWatchOptions(
            openMode: session.options.openMode,
            scope: session.options.scope,
            excludedSubdirectoryPaths: paths
        )

        let normalizedOld = session.options.encodedForFolder(session.folderURL)
        let normalizedNew = updatedOptions.encodedForFolder(session.folderURL)

        guard normalizedOld != normalizedNew else { return }

        try startWatching(
            folderURL: session.folderURL,
            options: updatedOptions,
            performInitialAutoOpen: false
        )
    }

    func dismissFolderWatchAutoOpenWarning() {
        folderWatchAutoOpenWarning = nil
    }

    func watchApplies(to fileURL: URL?) -> Bool {
        guard let fileURL,
              let session = activeFolderWatchSession else {
            return false
        }

        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(session.folderURL)

        switch session.options.scope {
        case .selectedFolderOnly:
            return normalizedFileURL.deletingLastPathComponent().path == normalizedFolderURL.path
        case .includeSubfolders:
            let folderPath = normalizedFolderURL.path.hasSuffix("/")
                ? normalizedFolderURL.path
                : normalizedFolderURL.path + "/"
            return normalizedFileURL.path.hasPrefix(folderPath)
        }
    }

    func watchApplies(normalizedFileURL: URL, toNormalizedFolderAt normalizedFolderURL: URL, scope: ReaderFolderWatchScope) -> Bool {
        switch scope {
        case .selectedFolderOnly:
            return normalizedFileURL.deletingLastPathComponent().path == normalizedFolderURL.path
        case .includeSubfolders:
            let folderPath = normalizedFolderURL.path.hasSuffix("/")
                ? normalizedFolderURL.path
                : normalizedFolderURL.path + "/"
            return normalizedFileURL.path.hasPrefix(folderPath)
        }
    }

    func scanCurrentMarkdownFiles(completion: @escaping @MainActor ([URL]) -> Void) {
        guard let session = activeFolderWatchSession else {
            completion([])
            return
        }

        if let cachedURLs = folderWatcher.cachedMarkdownFileURLs() {
            completion(cachedURLs)
            return
        }

        // Fall back to full enumeration if scan not yet complete
        let folderURL = session.folderURL
        let includeSubfolders = session.options.scope == .includeSubfolders
        let excludedURLs = session.options.resolvedExcludedSubdirectoryURLs(relativeTo: folderURL)
        let folderWatcher = self.folderWatcher

        if includeSubfolders {
            Task.detached(priority: .utility) {
                let urls = (try? folderWatcher.markdownFiles(
                    in: folderURL,
                    includeSubfolders: true,
                    excludedSubdirectoryURLs: excludedURLs
                )) ?? []

                await completion(urls)
            }
        } else {
            let urls = (try? folderWatcher.markdownFiles(
                in: folderURL,
                includeSubfolders: false,
                excludedSubdirectoryURLs: excludedURLs
            )) ?? []
            completion(urls)
        }
    }

    private func handleObservedWatchedFolderChanges(_ markdownFileEvents: [ReaderFolderWatchChangeEvent]) {
        guard let session = activeFolderWatchSession else {
            return
        }

        lastWatchedFolderEventAt = .now
        let livePlan = folderWatchAutoOpenPlanner.livePlan(
            for: eventsExcludingOpenDocuments(markdownFileEvents),
            activeSession: nil,
            currentDocumentFileURL: delegate?.folderWatchControllerCurrentDocumentFileURL(self)
        )
        let plannedEvents = livePlan.autoOpenEvents
        dispatchOpenEvents(plannedEvents, session: session, origin: .folderWatchAutoOpen)

        if !plannedEvents.isEmpty {
            delegate?.folderWatchController(self, didLiveAutoOpenFileURLs: plannedEvents.map(\.fileURL))
        }
    }

    private func eventsExcludingOpenDocuments(
        _ events: [ReaderFolderWatchChangeEvent]
    ) -> [ReaderFolderWatchChangeEvent] {
        let openDocumentURLs = Set((delegate?.folderWatchControllerOpenDocumentFileURLs(self) ?? []).map {
            ReaderFileRouting.normalizedFileURL($0)
        })

        guard !openDocumentURLs.isEmpty else {
            return events
        }

        return events.filter { event in
            !openDocumentURLs.contains(ReaderFileRouting.normalizedFileURL(event.fileURL))
        }
    }

    private func dispatchOpenEvents(
        _ events: [ReaderFolderWatchChangeEvent],
        session: ReaderFolderWatchSession,
        origin: ReaderOpenOrigin
    ) {
        guard !events.isEmpty else {
            return
        }

        if origin.shouldNotifyFileAutoLoaded,
           events.count == 1,
           settingsStore.currentSettings.notificationsEnabled {
            systemNotifier.notifyFileChanged(
                events[0].fileURL,
                changeKind: events[0].kind,
                watchedFolderURL: session.folderURL
            )
        }

        delegate?.folderWatchController(self, handleEvents: events, in: session, origin: origin)
    }

    private func loadInitialMarkdownFilesOffMainActor(
        for session: ReaderFolderWatchSession,
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) {
        initialMarkdownScanTask?.cancel()

        let folderWatcher = self.folderWatcher

        initialMarkdownScanTask = Task.detached(priority: .utility) { [weak self] in
            let markdownScanResult: Result<[URL], Error>
            do {
                let markdownURLs = try folderWatcher.markdownFiles(
                    in: folderURL,
                    includeSubfolders: includeSubfolders,
                    excludedSubdirectoryURLs: excludedSubdirectoryURLs
                )
                markdownScanResult = .success(markdownURLs)
            } catch {
                markdownScanResult = .failure(error)
            }

            guard !Task.isCancelled else {
                return
            }

            Task { @MainActor [weak self] in
                switch markdownScanResult {
                case let .success(markdownURLs):
                    self?.didInitialMarkdownScanFail = false
                    self?.applyInitialAutoOpenMarkdownURLs(markdownURLs, for: session)
                case .failure:
                    self?.applyInitialAutoOpenMarkdownScanFailure(for: session)
                }
                self?.initialMarkdownScanTask = nil
            }
        }
    }

    private func applyInitialAutoOpenMarkdownScanFailure(for session: ReaderFolderWatchSession) {
        guard activeFolderWatchSession == session else {
            return
        }

        didInitialMarkdownScanFail = true
        isInitialMarkdownScanInProgress = false
    }

    private func applyInitialAutoOpenMarkdownURLs(
        _ markdownURLs: [URL],
        for session: ReaderFolderWatchSession
    ) {
        guard activeFolderWatchSession == session else {
            return
        }

        if markdownURLs.count > ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount {
            pendingFileSelectionRequest = ReaderFolderWatchFileSelectionRequest(
                folderURL: session.folderURL,
                session: session,
                allFileURLs: markdownURLs
            )
            isInitialMarkdownScanInProgress = false
            return
        }

        pendingFileSelectionRequest = nil

        let currentDocumentFileURL = delegate?.folderWatchControllerCurrentDocumentFileURL(self)
        let eligibleURLs = markdownURLs.filter { url in
            let normalized = ReaderFileRouting.normalizedFileURL(url)
            if let currentDocumentFileURL,
               normalized == ReaderFileRouting.normalizedFileURL(currentDocumentFileURL) {
                return false
            }
            return true
        }

        let sortedByModDate = urlsSortedByModificationDateDescending(eligibleURLs)
        let maxLoad = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
        let loadURLs = Array(sortedByModDate.prefix(maxLoad))
        let deferURLs = Array(sortedByModDate.dropFirst(maxLoad))

        didInitialMarkdownScanFail = false
        folderWatchAutoOpenWarning = nil

        if !deferURLs.isEmpty {
            let deferEvents = deferURLs.map {
                ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
            }
            dispatchOpenEvents(deferEvents, session: session, origin: .folderWatchInitialBatchAutoOpen)
        }

        if !loadURLs.isEmpty {
            let loadEvents = loadURLs.map {
                ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
            }
            dispatchOpenEvents(loadEvents, session: session, origin: .folderWatchAutoOpen)
        }

        delegate?.folderWatchControllerShouldSelectNewestDocument(self)
        isInitialMarkdownScanInProgress = false
    }

    private func urlsSortedByModificationDateDescending(_ urls: [URL]) -> [URL] {
        urls.map { url -> (url: URL, modDate: Date) in
            let modDate = (try? FileManager.default.attributesOfItem(
                atPath: url.path
            ))?[.modificationDate] as? Date ?? .distantPast
            return (url, modDate)
        }
        .sorted { $0.modDate > $1.modDate }
        .map(\.url)
    }
}
