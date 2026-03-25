import Foundation
import OSLog

enum ReaderFolderWatchChangeKind: String, Equatable, Hashable, Codable, Sendable {
    case added
    case modified
}

struct ReaderFolderWatchChangeEvent: Equatable, Hashable, Codable, Sendable {
    let fileURL: URL
    let kind: ReaderFolderWatchChangeKind
    let previousMarkdown: String?

    init(fileURL: URL, kind: ReaderFolderWatchChangeKind, previousMarkdown: String? = nil) {
        self.fileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        self.kind = kind
        self.previousMarkdown = previousMarkdown
    }
}

protocol FolderChangeWatching: AnyObject, Sendable {
    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL],
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws

    func stopWatching()

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL]
}

extension FolderChangeWatching {
    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws {
        try startWatching(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            excludedSubdirectoryURLs: [],
            onMarkdownFilesAddedOrChanged: onMarkdownFilesAddedOrChanged
        )
    }

    func markdownFiles(in folderURL: URL, includeSubfolders: Bool) throws -> [URL] {
        try markdownFiles(
            in: folderURL,
            includeSubfolders: includeSubfolders,
            excludedSubdirectoryURLs: []
        )
    }
}

struct FolderChangeWatcherFailure: Equatable, Sendable {
    enum Stage: String, Equatable, Sendable {
        case startupSnapshot
        case verificationSnapshot
        case watchedDirectoryEnumeration
    }

    let stage: Stage
    let folderIdentifier: String
    let errorDescription: String
}

final class FolderChangeWatcher: FolderChangeWatching, @unchecked Sendable {
    private static let adaptiveSafetyPollingIdleCyclesPerStep = 3
    private static let adaptiveSafetyPollingMaximumMultiplier = 4
    private static let adaptiveSafetyPollingMaximumUnsignaledSkips = 2
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "FolderChangeWatcher"
    )
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "FolderWatchProfiling"
    )
    private let queue = DispatchQueue(label: "minimark.folderwatcher")
    private let pollingInterval: DispatchTimeInterval
    private let fallbackPollingInterval: DispatchTimeInterval
    private let recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval
    private let verificationDelay: DispatchTimeInterval
    private let maximumDirectoryEventSourceCount: Int
    private let onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)?
    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var timer: DispatchSourceTimer?
    private var timerInterval: DispatchTimeInterval?
    private var pendingWorkItem: DispatchWorkItem?
    private var usesEventSource = false
    private var needsDirectorySourceResync = false
    private var adaptiveSafetyPollingMultiplier = 1
    private var adaptiveSafetyPollingIdleCycles = 0
    private var unsignaledVerificationSkipCycles = 0
    private var hasPendingFileSystemSignal = false

    private var watchedFolderURL: URL?
    private var includesSubfolders = false
    private var excludedSubdirectoryURLs: [URL] = []
    private var exclusionMatcher: FolderWatchExclusionMatcher?
    private var onMarkdownFilesAddedOrChanged: (([ReaderFolderWatchChangeEvent]) -> Void)?
    private var lastSnapshot: [URL: FolderFileSnapshot] = [:]
    private var lastReportedFailureByStage: [FolderChangeWatcherFailure.Stage: String] = [:]
    private var startupSequence: UInt64 = 0
    private var didCompleteStartup = false

    convenience init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval = .seconds(
            ReaderFolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
        ),
        verificationDelay: DispatchTimeInterval = .milliseconds(75),
        onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)? = nil
    ) {
        self.init(
            pollingInterval: pollingInterval,
            fallbackPollingInterval: fallbackPollingInterval,
            recursiveEventSourceSafetyPollingInterval: recursiveEventSourceSafetyPollingInterval,
            verificationDelay: verificationDelay,
            maximumDirectoryEventSourceCount: 128,
            onFailure: onFailure
        )
    }

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval = .seconds(
            ReaderFolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
        ),
        verificationDelay: DispatchTimeInterval = .milliseconds(75),
        maximumDirectoryEventSourceCount: Int = 128,
        onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)? = nil
    ) {
        self.pollingInterval = pollingInterval
        self.fallbackPollingInterval = fallbackPollingInterval
        self.recursiveEventSourceSafetyPollingInterval = recursiveEventSourceSafetyPollingInterval
        self.verificationDelay = verificationDelay
        self.maximumDirectoryEventSourceCount = max(1, maximumDirectoryEventSourceCount)
        self.onFailure = onFailure
        queue.setSpecific(key: Self.queueKey, value: 1)
    }

    deinit {
        stopWatching()
    }

    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL] = [],
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws {
        stopWatching()

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard normalizedFolderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        let normalizedExcludedSubdirectoryURLs = excludedSubdirectoryURLs.map(ReaderFileRouting.normalizedFileURL)
        let sequence = queue.sync { () -> UInt64 in
            startupSequence &+= 1
            let nextSequence = startupSequence

            watchedFolderURL = normalizedFolderURL
            includesSubfolders = includeSubfolders
            self.excludedSubdirectoryURLs = normalizedExcludedSubdirectoryURLs
            self.exclusionMatcher = FolderWatchExclusionMatcher(
                rootFolderURL: normalizedFolderURL,
                excludedSubdirectoryURLs: normalizedExcludedSubdirectoryURLs
            )
            self.onMarkdownFilesAddedOrChanged = onMarkdownFilesAddedOrChanged
            lastSnapshot = [:]
            lastReportedFailureByStage = [:]
            needsDirectorySourceResync = false
            didCompleteStartup = false
            unsignaledVerificationSkipCycles = 0
            hasPendingFileSystemSignal = true

            return nextSequence
        }

        queue.async { [weak self] in
            self?.completeAsyncStartup(
                folderURL: normalizedFolderURL,
                includeSubfolders: includeSubfolders,
                excludedSubdirectoryURLs: normalizedExcludedSubdirectoryURLs,
                startupSequence: sequence
            )
        }
    }

    func stopWatching() {
        let stopWork = {
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil

            self.cancelAllDirectorySources()

            self.timer?.cancel()
            self.timer = nil
            self.timerInterval = nil

            self.watchedFolderURL = nil
            self.includesSubfolders = false
            self.excludedSubdirectoryURLs = []
            self.exclusionMatcher = nil
            self.onMarkdownFilesAddedOrChanged = nil
            self.lastSnapshot = [:]
            self.lastReportedFailureByStage = [:]
            self.usesEventSource = false
            self.needsDirectorySourceResync = false
            self.adaptiveSafetyPollingMultiplier = 1
            self.adaptiveSafetyPollingIdleCycles = 0
            self.unsignaledVerificationSkipCycles = 0
            self.hasPendingFileSystemSignal = false
            self.didCompleteStartup = false
            self.startupSequence &+= 1
        }

        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopWork()
        } else {
            queue.sync(execute: stopWork)
        }
    }

    private func completeAsyncStartup(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL],
        startupSequence: UInt64
    ) {
        guard startupSequence == self.startupSequence else {
            return
        }

        let snapshot: [URL: FolderFileSnapshot]
        do {
            snapshot = try buildSnapshot(
                folderURL: folderURL,
                includeSubfolders: includeSubfolders,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
            clearReportedFailure(for: .startupSnapshot)
        } catch {
            // Keep startup resilient by preserving empty-baseline behavior while surfacing the failure.
            snapshot = [:]
            reportFailure(stage: .startupSnapshot, folderURL: folderURL, error: error)
        }

        guard startupSequence == self.startupSequence else {
            return
        }

        lastSnapshot = snapshot

        synchronizeDirectorySources(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            excludedSubdirectoryURLs: excludedSubdirectoryURLs
        )
        needsDirectorySourceResync = false
        didCompleteStartup = true
        reconfigureTimerIfNeeded()
        scheduleVerification()
    }

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL] = []
    ) throws -> [URL] {
        try enumerateMarkdownFiles(
            folderURL: ReaderFileRouting.normalizedFileURL(folderURL),
            includeSubfolders: includeSubfolders,
            exclusionMatcher: FolderWatchExclusionMatcher(
                rootFolderURL: ReaderFileRouting.normalizedFileURL(folderURL),
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
        ).sorted(by: { $0.path < $1.path })
    }

    var isUsingEventSourcesForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return usesEventSource
        }

        return queue.sync { usesEventSource }
    }

    var activeDirectorySourceCountForTesting: Int {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return directorySources.count
        }

        return queue.sync { directorySources.count }
    }

    var isUsingFallbackPollingIntervalForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval == fallbackPollingInterval
        }

        return queue.sync { timerInterval == fallbackPollingInterval }
    }

    var isUsingRecursiveEventSourceSafetyPollingIntervalForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval == resolvedRecursiveEventSourceSafetyPollingInterval()
        }

        return queue.sync { timerInterval == resolvedRecursiveEventSourceSafetyPollingInterval() }
    }

    var currentTimerIntervalForTesting: DispatchTimeInterval? {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval
        }

        return queue.sync { timerInterval }
    }

    var didCompleteStartupForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return didCompleteStartup
        }

        return queue.sync { didCompleteStartup }
    }

    private func scheduleVerification() {
        guard pendingWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingWorkItem = nil
            self?.verifyChanges()
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + verificationDelay, execute: workItem)
    }

    private func verifyChanges() {
        let verifySignpostID = Self.signposter.makeSignpostID()
        let verifyIntervalState = Self.signposter.beginInterval("verifyChanges", id: verifySignpostID)
        defer {
            Self.signposter.endInterval("verifyChanges", verifyIntervalState)
        }

        guard let watchedFolderURL, let onMarkdownFilesAddedOrChanged else {
            return
        }

        guard let exclusionMatcher else {
            return
        }

        if shouldSkipIdleVerificationCycle() {
            adaptRecursiveEventSourceSafetyPollingIfNeeded(
                changedEventCount: 0,
                didResynchronizeDirectories: false
            )
            return
        }

        hasPendingFileSystemSignal = false
        unsignaledVerificationSkipCycles = 0

        let currentSnapshot: [URL: FolderFileSnapshot]
        do {
            let snapshotIntervalState = Self.signposter.beginInterval("buildIncrementalSnapshot", id: verifySignpostID)
            defer {
                Self.signposter.endInterval("buildIncrementalSnapshot", snapshotIntervalState)
            }
            currentSnapshot = try buildIncrementalSnapshot(
                folderURL: watchedFolderURL,
                includeSubfolders: includesSubfolders,
                exclusionMatcher: exclusionMatcher,
                previousSnapshot: lastSnapshot
            )
            Self.signposter.emitEvent(
                "snapshotCounts",
                "current \(currentSnapshot.count) previous \(self.lastSnapshot.count) include_subfolders \(self.includesSubfolders ? 1 : 0)"
            )
            clearReportedFailure(for: .verificationSnapshot)
        } catch {
            reportFailure(stage: .verificationSnapshot, folderURL: watchedFolderURL, error: error)
            return
        }

        var didResynchronizeDirectories = false
        if needsDirectorySourceResync {
            let resyncIntervalState = Self.signposter.beginInterval("synchronizeDirectorySources", id: verifySignpostID)
            synchronizeDirectorySources(
                folderURL: watchedFolderURL,
                includeSubfolders: includesSubfolders,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
            Self.signposter.endInterval("synchronizeDirectorySources", resyncIntervalState)
            needsDirectorySourceResync = false
            didResynchronizeDirectories = true
        }

        let diffIntervalState = Self.signposter.beginInterval("diffSnapshots", id: verifySignpostID)
        var changedEvents: [ReaderFolderWatchChangeEvent] = []
        for (url, currentFingerprint) in currentSnapshot {
            if let previous = lastSnapshot[url] {
                if previous.hasMeaningfulModification(comparedTo: currentFingerprint) {
                    changedEvents.append(
                        ReaderFolderWatchChangeEvent(
                            fileURL: url,
                            kind: .modified,
                            previousMarkdown: previous.markdown
                        )
                    )
                }
            } else {
                changedEvents.append(
                    ReaderFolderWatchChangeEvent(fileURL: url, kind: .added)
                )
            }
        }
        Self.signposter.endInterval("diffSnapshots", diffIntervalState)
        Self.signposter.emitEvent(
            "diffCounts",
            "changed \(changedEvents.count) current \(currentSnapshot.count)"
        )

        adaptRecursiveEventSourceSafetyPollingIfNeeded(
            changedEventCount: changedEvents.count,
            didResynchronizeDirectories: didResynchronizeDirectories
        )

        lastSnapshot = currentSnapshot
        guard !changedEvents.isEmpty else {
            return
        }

        let normalized = changedEvents.sorted(by: { $0.fileURL.path < $1.fileURL.path })

        DispatchQueue.main.async {
            onMarkdownFilesAddedOrChanged(normalized)
        }
    }

    private func buildSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL: FolderFileSnapshot] {
        var snapshot: [URL: FolderFileSnapshot] = [:]
        let markdownURLs = try enumerateMarkdownFiles(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: FolderWatchExclusionMatcher(
                rootFolderURL: folderURL,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
        )

        for url in markdownURLs {
            snapshot[url] = FolderFileSnapshot(url: url)
        }

        return snapshot
    }

    private func synchronizeDirectorySources(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) {
        let usedEventSourcesBeforeSync = usesEventSource
        let exclusionMatcher = FolderWatchExclusionMatcher(
            rootFolderURL: folderURL,
            excludedSubdirectoryURLs: excludedSubdirectoryURLs
        )
        let watchedDirectoryURLs: [URL]
        do {
            watchedDirectoryURLs = try enumerateWatchedDirectories(
                folderURL: folderURL,
                includeSubfolders: includeSubfolders,
                exclusionMatcher: exclusionMatcher
            )
            Self.signposter.emitEvent(
                "watchedDirectoryEnumeration",
                "directories \(watchedDirectoryURLs.count) include_subfolders \(includeSubfolders ? 1 : 0)"
            )
            clearReportedFailure(for: .watchedDirectoryEnumeration)
        } catch {
            watchedDirectoryURLs = [folderURL]
            reportFailure(stage: .watchedDirectoryEnumeration, folderURL: folderURL, error: error)
        }

        if includeSubfolders && watchedDirectoryURLs.count > maximumDirectoryEventSourceCount {
            cancelAllDirectorySources()
            if usedEventSourcesBeforeSync != usesEventSource {
                reconfigureTimerIfNeeded()
            }
            return
        }

        let targetURLs = Set(watchedDirectoryURLs)

        for url in directorySources.keys where !targetURLs.contains(url) {
            directorySources[url]?.cancel()
            directorySources.removeValue(forKey: url)
        }

        for url in watchedDirectoryURLs where directorySources[url] == nil {
            guard let source = makeDirectorySource(for: url) else {
                continue
            }

            directorySources[url] = source
            source.resume()
        }

        usesEventSource = !directorySources.isEmpty
        Self.signposter.emitEvent(
            "directorySourceCounts",
            "sources \(self.directorySources.count) uses_event_sources \(self.usesEventSource ? 1 : 0)"
        )
        if usedEventSourcesBeforeSync != usesEventSource {
            reconfigureTimerIfNeeded()
        }
    }

    private func reconfigureTimerIfNeeded() {
        let desiredInterval: DispatchTimeInterval
        if usesEventSource {
            desiredInterval = includesSubfolders
                ? resolvedRecursiveEventSourceSafetyPollingInterval()
                : fallbackPollingInterval
        } else {
            desiredInterval = pollingInterval
        }

        guard timer == nil || timerInterval != desiredInterval else {
            return
        }

        timer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + desiredInterval, repeating: desiredInterval)
        timer.setEventHandler { [weak self] in
            self?.verifyChanges()
        }
        self.timer = timer
        timerInterval = desiredInterval
        timer.resume()
    }

    private func makeDirectorySource(for directoryURL: URL) -> DispatchSourceFileSystemObject? {
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else {
                return
            }

            let events = source.data
            self.handleDirectorySourceEvent(events)
            self.scheduleVerification()
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        return source
    }

    private func cancelAllDirectorySources() {
        for source in directorySources.values {
            source.cancel()
        }

        directorySources.removeAll()
        usesEventSource = false
    }

    private func handleDirectorySourceEvent(_ events: DispatchSource.FileSystemEvent) {
        resetAdaptiveSafetyPollingToBaselineIfNeeded()
        hasPendingFileSystemSignal = true
        unsignaledVerificationSkipCycles = 0

        let topologyChangeEvents: DispatchSource.FileSystemEvent = [.rename, .delete, .revoke, .write]
        if !events.intersection(topologyChangeEvents).isEmpty {
            needsDirectorySourceResync = needsDirectorySourceResync || includesSubfolders
        }
    }

    private func resolvedRecursiveEventSourceSafetyPollingInterval() -> DispatchTimeInterval {
        scaledInterval(recursiveEventSourceSafetyPollingInterval, multiplier: adaptiveSafetyPollingMultiplier)
    }

    private func adaptRecursiveEventSourceSafetyPollingIfNeeded(
        changedEventCount: Int,
        didResynchronizeDirectories: Bool
    ) {
        guard usesEventSource, includesSubfolders else {
            adaptiveSafetyPollingMultiplier = 1
            adaptiveSafetyPollingIdleCycles = 0
            return
        }

        guard changedEventCount == 0, !didResynchronizeDirectories else {
            resetAdaptiveSafetyPollingToBaselineIfNeeded()
            return
        }

        adaptiveSafetyPollingIdleCycles += 1
        guard adaptiveSafetyPollingIdleCycles >= Self.adaptiveSafetyPollingIdleCyclesPerStep else {
            return
        }

        adaptiveSafetyPollingIdleCycles = 0
        guard adaptiveSafetyPollingMultiplier < Self.adaptiveSafetyPollingMaximumMultiplier else {
            return
        }

        adaptiveSafetyPollingMultiplier += 1
        reconfigureTimerIfNeeded()
    }

    private func resetAdaptiveSafetyPollingToBaselineIfNeeded() {
        adaptiveSafetyPollingIdleCycles = 0
        guard adaptiveSafetyPollingMultiplier != 1 else {
            return
        }

        adaptiveSafetyPollingMultiplier = 1
        reconfigureTimerIfNeeded()
    }

    private func shouldSkipIdleVerificationCycle() -> Bool {
        guard usesEventSource,
              includesSubfolders,
              !needsDirectorySourceResync,
              !hasPendingFileSystemSignal else {
            unsignaledVerificationSkipCycles = 0
            return false
        }

        guard unsignaledVerificationSkipCycles < Self.adaptiveSafetyPollingMaximumUnsignaledSkips else {
            unsignaledVerificationSkipCycles = 0
            return false
        }

        unsignaledVerificationSkipCycles += 1
        return true
    }

    private func scaledInterval(_ interval: DispatchTimeInterval, multiplier: Int) -> DispatchTimeInterval {
        guard multiplier > 1 else {
            return interval
        }

        switch interval {
        case let .seconds(value):
            return .seconds(value * multiplier)
        case let .milliseconds(value):
            return .milliseconds(value * multiplier)
        case let .microseconds(value):
            return .microseconds(value * multiplier)
        case let .nanoseconds(value):
            return .nanoseconds(value * multiplier)
        case .never:
            return .never
        @unknown default:
            return interval
        }
    }

    private func buildIncrementalSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher,
        previousSnapshot: [URL: FolderFileSnapshot]
    ) throws -> [URL: FolderFileSnapshot] {
        let snapshotSignpostID = Self.signposter.makeSignpostID()
        let snapshotIntervalState = Self.signposter.beginInterval("buildIncrementalSnapshot.total", id: snapshotSignpostID)
        defer {
            Self.signposter.endInterval("buildIncrementalSnapshot.total", snapshotIntervalState)
        }

        let markdownURLs = try enumerateMarkdownFiles(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: exclusionMatcher
        )
        var snapshot: [URL: FolderFileSnapshot] = [:]
        snapshot.reserveCapacity(markdownURLs.count)

        for url in markdownURLs {
            let metadata = FolderFileMetadata(url: url)
            if let previous = previousSnapshot[url], previous.matches(metadata: metadata) {
                snapshot[url] = previous
                continue
            }

            snapshot[url] = FolderFileSnapshot(url: url, metadata: metadata)
        }

        return snapshot
    }

    private func enumerateMarkdownFiles(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) throws -> [URL] {
        let enumerateSignpostID = Self.signposter.makeSignpostID()
        let enumerateIntervalState = Self.signposter.beginInterval("enumerateMarkdownFiles", id: enumerateSignpostID)
        defer {
            Self.signposter.endInterval("enumerateMarkdownFiles", enumerateIntervalState)
        }

        guard folderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        let fileManager = FileManager.default

        if includeSubfolders {
            let rootFolderPathWithSlash = exclusionMatcher.normalizedRootPathWithSlash
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else {
                return []
            }

            var result: [URL] = []
            for case let fileURL as URL in enumerator {
                let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
                if shouldSkipEntryBeyondIncludeSubfolderDepth(
                    normalizedFileURL,
                    rootFolderPathWithSlash: rootFolderPathWithSlash,
                    enumerator: enumerator
                   ) {
                    continue
                }

                if shouldSkipDescendants(
                    forNormalizedURL: normalizedFileURL,
                    exclusionMatcher: exclusionMatcher,
                    enumerator: enumerator
                ) {
                    continue
                }

                if let markdownFileURL = regularMarkdownFileURL(fromNormalized: normalizedFileURL) {
                    guard !exclusionMatcher.excludesNormalizedFilePath(markdownFileURL.path) else {
                        continue
                    }
                    result.append(markdownFileURL)
                }
            }

            Self.signposter.emitEvent(
                "enumeratedMarkdownFilesCount",
                "files \(result.count) include_subfolders 1"
            )

            return result
        } else {
            let urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
            let result = urls
                .map(ReaderFileRouting.normalizedFileURL)
                .compactMap(regularMarkdownFileURL(fromNormalized:))
                .filter { !exclusionMatcher.excludesNormalizedFilePath($0.path) }
            Self.signposter.emitEvent(
                "enumeratedMarkdownFilesCount",
                "files \(result.count) include_subfolders 0"
            )

            return result
        }
    }

    private func enumerateWatchedDirectories(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) throws -> [URL] {
        guard folderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard includeSubfolders else {
            return [normalizedFolderURL]
        }

        var result: [URL] = [normalizedFolderURL]
        let fileManager = FileManager.default
        let rootFolderPathWithSlash = exclusionMatcher.normalizedRootPathWithSlash

        guard let enumerator = fileManager.enumerator(
            at: normalizedFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return result
        }

        for case let directoryURL as URL in enumerator {
            let normalizedDirectoryURL = ReaderFileRouting.normalizedFileURL(directoryURL)
            if shouldSkipEntryBeyondIncludeSubfolderDepth(
                normalizedDirectoryURL,
                rootFolderPathWithSlash: rootFolderPathWithSlash,
                enumerator: enumerator
               ) {
                continue
            }

            if shouldSkipDescendants(
                forNormalizedURL: normalizedDirectoryURL,
                exclusionMatcher: exclusionMatcher,
                enumerator: enumerator
            ) {
                continue
            }

            if (try? normalizedDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard !exclusionMatcher.excludesNormalizedDirectoryPath(normalizedDirectoryURL.path) else {
                    continue
                }
                result.append(normalizedDirectoryURL)
            }
        }

        return result
    }

    private func regularMarkdownFileURL(fromNormalized normalizedFileURL: URL) -> URL? {
        guard ReaderFileRouting.isSupportedMarkdownFileURL(normalizedFileURL) else {
            return nil
        }

        let isRegularFile = (try? normalizedFileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegularFile else {
            return nil
        }

        return normalizedFileURL
    }

    private func shouldSkipDescendants(
        forNormalizedURL normalizedURL: URL,
        exclusionMatcher: FolderWatchExclusionMatcher,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        guard exclusionMatcher.excludesNormalizedDirectoryPath(normalizedURL.path) else {
            return false
        }

        enumerator.skipDescendants()
        return true
    }

    private func shouldSkipEntryBeyondIncludeSubfolderDepth(
        _ normalizedURL: URL,
        rootFolderPathWithSlash: String,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        let isDirectory = (try? normalizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let depth = relativePathDepth(
            forPath: normalizedURL.path,
            relativeToPathWithSlash: rootFolderPathWithSlash,
            isDirectory: isDirectory
        )

        guard depth > ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth else {
            return false
        }

        if isDirectory {
            enumerator.skipDescendants()
        }

        return true
    }

    private func relativePathDepth(forPath path: String, relativeToPathWithSlash rootPathWithSlash: String, isDirectory: Bool) -> Int {
        let rootPath = String(rootPathWithSlash.dropLast())

        if path == rootPath {
            return 0
        }

        guard path.hasPrefix(rootPathWithSlash) else {
            return .max
        }

        let relativePath = String(path.dropFirst(rootPathWithSlash.count))
        guard !relativePath.isEmpty else {
            return 0
        }

        let componentCount = relativePath.split(separator: "/", omittingEmptySubsequences: true).count
        guard !isDirectory else {
            return componentCount
        }

        // Files should be allowed up to the maximum directory depth, so we do not
        // count the file name itself as an additional level.
        return max(0, componentCount - 1)
    }

    private func reportFailure(stage: FolderChangeWatcherFailure.Stage, folderURL: URL, error: any Error) {
        let errorDescription = sanitizedErrorDescription(for: error)
        let failure = FolderChangeWatcherFailure(
            stage: stage,
            folderIdentifier: sanitizedFolderIdentifier(for: folderURL),
            errorDescription: errorDescription
        )

        let signature = stableErrorKey(for: error)
        if lastReportedFailureByStage[stage] != signature {
            lastReportedFailureByStage[stage] = signature
            Self.logger.error(
                "folder watch failure stage=\(stage.rawValue, privacy: .public) folder=\(folderURL.path, privacy: .private(mask: .hash)) error=\(errorDescription, privacy: .private(mask: .hash))"
            )

            let onFailure = self.onFailure
            DispatchQueue.main.async {
                onFailure?(failure)
            }
        }
    }

    private func clearReportedFailure(for stage: FolderChangeWatcherFailure.Stage) {
        lastReportedFailureByStage.removeValue(forKey: stage)
    }

    private func sanitizedFolderIdentifier(for folderURL: URL) -> String {
        let normalizedPath = ReaderFileRouting.normalizedFileURL(folderURL).path
        return String(normalizedPath.hashValue, radix: 16)
    }

    private func sanitizedErrorDescription(for error: any Error) -> String {
        let nsError = error as NSError
        return "domain: \(nsError.domain), code: \(nsError.code)"
    }

    private func stableErrorKey(for error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

private struct FolderWatchExclusionMatcher {
    private let rootFolderPathWithSlash: String
    private let excludedDirectoryPaths: [String]

    init(rootFolderURL: URL, excludedSubdirectoryURLs: [URL]) {
        let normalizedRootURL = ReaderFileRouting.normalizedFileURL(rootFolderURL)
        let rootPath = normalizedRootURL.path
        let rootFolderPathWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        self.rootFolderPathWithSlash = rootFolderPathWithSlash

        self.excludedDirectoryPaths = excludedSubdirectoryURLs
            .map(ReaderFileRouting.normalizedFileURL)
            .map(\.path)
            .filter { $0.hasPrefix(rootFolderPathWithSlash) }
            .sorted()
    }

    var normalizedRootPathWithSlash: String {
        rootFolderPathWithSlash
    }

    func excludesDirectory(_ directoryURL: URL) -> Bool {
        excludesNormalizedDirectoryPath(ReaderFileRouting.normalizedFileURL(directoryURL).path)
    }

    func excludesFile(_ fileURL: URL) -> Bool {
        excludesNormalizedFilePath(ReaderFileRouting.normalizedFileURL(fileURL).path)
    }

    func excludesNormalizedDirectoryPath(_ normalizedPath: String) -> Bool {
        excludesPath(normalizedPath)
    }

    func excludesNormalizedFilePath(_ normalizedPath: String) -> Bool {
        excludesPath(normalizedPath)
    }

    private func excludesPath(_ path: String) -> Bool {
        for excludedPath in excludedDirectoryPaths {
            if path == excludedPath {
                return true
            }

            let excludedPrefix = excludedPath.hasSuffix("/") ? excludedPath : excludedPath + "/"
            if path.hasPrefix(excludedPrefix) {
                return true
            }
        }

        return false
    }
}

private struct FolderFileSnapshot: Equatable {
    let fileSize: UInt64
    let modificationDate: Date
    let resourceIdentity: String
    let markdown: String?

    init(url: URL) {
        self.init(url: url, metadata: FolderFileMetadata(url: url))
    }

    init(url: URL, metadata: FolderFileMetadata) {
        fileSize = metadata.fileSize
        modificationDate = metadata.modificationDate
        resourceIdentity = metadata.resourceIdentity
        markdown = metadata.exists ? (try? String(contentsOf: url, encoding: .utf8)) : nil
    }

    func matches(metadata: FolderFileMetadata) -> Bool {
        fileSize == metadata.fileSize &&
            modificationDate == metadata.modificationDate &&
            resourceIdentity == metadata.resourceIdentity
    }

    func hasMeaningfulModification(comparedTo current: FolderFileSnapshot) -> Bool {
        markdown != current.markdown
    }
}

private struct FolderFileMetadata: Equatable {
    let exists: Bool
    let fileSize: UInt64
    let modificationDate: Date
    let resourceIdentity: String

    init(url: URL) {
        let path = url.path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let type = attributes[.type] as? FileAttributeType,
           type == .typeRegular {
            exists = true
            fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast

            if let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value {
                resourceIdentity = String(inode)
            } else if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
                      let fileResourceIdentifier = values.fileResourceIdentifier {
                resourceIdentity = String(describing: fileResourceIdentifier)
            } else {
                resourceIdentity = "none"
            }
        } else {
            exists = false
            fileSize = 0
            modificationDate = .distantPast
            resourceIdentity = "missing"
        }
    }
}
