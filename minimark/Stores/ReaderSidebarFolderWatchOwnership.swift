import Foundation

@MainActor
final class ReaderFolderWatchController {
    private let folderWatcher: FolderChangeWatching
    private let settingsStore: ReaderSettingsStoring
    private let securityScope: SecurityScopedResourceAccessing
    private let systemNotifier: ReaderSystemNotifying
    private let folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanning

    private var folderSecurityScopeToken: SecurityScopedAccessToken?

    var currentDocumentFileURLProvider: (() -> URL?)?
    var openDocumentFileURLsProvider: (() -> [URL])?
    var openEventsHandler: (([ReaderFolderWatchChangeEvent], ReaderFolderWatchSession, ReaderOpenOrigin) -> Void)?
    var onStateChange: (() -> Void)?

    private(set) var activeFolderWatchSession: ReaderFolderWatchSession? {
        didSet { onStateChange?() }
    }

    private(set) var lastWatchedFolderEventAt: Date? {
        didSet { onStateChange?() }
    }

    private(set) var folderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning? {
        didSet { onStateChange?() }
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

    convenience init(settingsStore: ReaderSettingsStoring) {
        self.init(
            folderWatcher: FolderChangeWatcher(),
            settingsStore: settingsStore,
            securityScope: SecurityScopedResourceAccess(),
            systemNotifier: ReaderSystemNotifier.shared,
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
    }

    var isWatchingFolder: Bool {
        activeFolderWatchSession != nil
    }

    func startWatching(folderURL: URL, options: ReaderFolderWatchOptions) throws {
        stopWatching()
        folderWatchAutoOpenWarning = nil
        folderWatchAutoOpenPlanner.resetTransientState()

        let accessibleFolderURL = folderURL
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(accessibleFolderURL)
        folderSecurityScopeToken = securityScope.beginAccess(to: accessibleFolderURL)

        do {
            try folderWatcher.startWatching(
                folderURL: accessibleFolderURL,
                includeSubfolders: options.scope == .includeSubfolders
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

            guard options.openMode == .openAllMarkdownFiles else {
                return
            }

            let markdownURLs = try folderWatcher.markdownFiles(
                in: accessibleFolderURL,
                includeSubfolders: options.scope == .includeSubfolders
            )
            let initialMarkdownEvents = markdownURLs.map {
                ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
            }
            let initialPlan = folderWatchAutoOpenPlanner.initialPlan(
                for: initialMarkdownEvents,
                activeSession: session,
                currentDocumentFileURL: currentDocumentFileURLProvider?()
            )

            folderWatchAutoOpenWarning = initialPlan.warning
            let initialOpenOrigin: ReaderOpenOrigin = initialPlan.autoOpenEvents.count > 1
                ? .folderWatchInitialBatchAutoOpen
                : .folderWatchAutoOpen
            dispatchOpenEvents(initialPlan.autoOpenEvents, session: session, origin: initialOpenOrigin)
        } catch {
            folderWatcher.stopWatching()
            folderSecurityScopeToken?.endAccess()
            folderSecurityScopeToken = nil
            activeFolderWatchSession = nil
            lastWatchedFolderEventAt = nil
            folderWatchAutoOpenWarning = nil
            throw error
        }
    }

    func stopWatching() {
        folderWatcher.stopWatching()
        folderWatchAutoOpenPlanner.resetTransientState()
        folderSecurityScopeToken?.endAccess()
        folderSecurityScopeToken = nil
        activeFolderWatchSession = nil
        lastWatchedFolderEventAt = nil
        folderWatchAutoOpenWarning = nil
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

    private func handleObservedWatchedFolderChanges(_ markdownFileEvents: [ReaderFolderWatchChangeEvent]) {
        guard let session = activeFolderWatchSession else {
            return
        }

        lastWatchedFolderEventAt = .now
        let livePlan = folderWatchAutoOpenPlanner.livePlan(
            for: eventsExcludingOpenDocuments(markdownFileEvents),
            activeSession: session,
            currentDocumentFileURL: currentDocumentFileURLProvider?()
        )
        if let warning = livePlan.warning {
            folderWatchAutoOpenWarning = warning
        }
        let plannedEvents = livePlan.autoOpenEvents
        dispatchOpenEvents(plannedEvents, session: session, origin: .folderWatchAutoOpen)
    }

    private func eventsExcludingOpenDocuments(
        _ events: [ReaderFolderWatchChangeEvent]
    ) -> [ReaderFolderWatchChangeEvent] {
        let openDocumentURLs = Set((openDocumentFileURLsProvider?() ?? []).map {
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
            systemNotifier.notifyFileAutoLoaded(
                events[0].fileURL,
                changeKind: events[0].kind,
                watchedFolderURL: session.folderURL
            )
        }

        openEventsHandler?(events, session, origin)
    }
}
