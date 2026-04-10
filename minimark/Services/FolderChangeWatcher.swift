import Foundation
import OSLog

protocol FolderChangeWatching: AnyObject, Sendable {
    var scanProgressStream: AsyncStream<FolderChangeWatcher.ScanProgress> { get }

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

    func cachedMarkdownFileURLs() -> [URL]?
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
    struct ScanProgress: Equatable, Sendable {
        let completed: Int
        let total: Int
        var isFinished: Bool { completed == total }
    }

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
    private let snapshotDiffer: FolderSnapshotDiffing
    private let verificationDelay: DispatchTimeInterval
    private let makeEventSource: (_ includeSubfolders: Bool) -> any FolderEventSource
    private let onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)?
    private var eventSource: (any FolderEventSource)?
    private var safetyTimer: DispatchSourceTimer?
    private var pendingWorkItem: DispatchWorkItem?

    private var watchedFolderURL: URL?
    private var includesSubfolders = false
    private var excludedSubdirectoryURLs: [URL] = []
    private var exclusionMatcher: FolderWatchExclusionMatcher?
    private var onMarkdownFilesAddedOrChanged: (([ReaderFolderWatchChangeEvent]) -> Void)?
    private var lastSnapshot: [URL: FolderFileSnapshot] = [:]
    private var lastReportedFailureByStage: [FolderChangeWatcherFailure.Stage: String] = [:]
    private var startupSequence: UInt64 = 0
    private var didCompleteStartup = false
    private var scanProgressContinuation: AsyncStream<ScanProgress>.Continuation?
    private var _scanProgressStream: AsyncStream<ScanProgress>?

    convenience init(
        verificationDelay: DispatchTimeInterval = .milliseconds(75),
        onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)? = nil
    ) {
        self.init(
            snapshotDiffer: FolderSnapshotDiffer(),
            verificationDelay: verificationDelay,
            makeEventSource: { FolderEventSourceFactory.makeEventSource(includeSubfolders: $0) },
            onFailure: onFailure
        )
    }

    init(
        snapshotDiffer: FolderSnapshotDiffing = FolderSnapshotDiffer(),
        verificationDelay: DispatchTimeInterval = .milliseconds(75),
        makeEventSource: @escaping (_ includeSubfolders: Bool) -> any FolderEventSource
            = { FolderEventSourceFactory.makeEventSource(includeSubfolders: $0) },
        onFailure: (@Sendable (FolderChangeWatcherFailure) -> Void)? = nil
    ) {
        self.snapshotDiffer = snapshotDiffer
        self.verificationDelay = verificationDelay
        self.makeEventSource = makeEventSource
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
            didCompleteStartup = false

            let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
            _scanProgressStream = stream
            scanProgressContinuation = continuation

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

            self.eventSource?.stop()
            self.eventSource = nil

            self.safetyTimer?.cancel()
            self.safetyTimer = nil

            self.watchedFolderURL = nil
            self.includesSubfolders = false
            self.excludedSubdirectoryURLs = []
            self.exclusionMatcher = nil
            self.onMarkdownFilesAddedOrChanged = nil
            self.lastSnapshot = [:]
            self.lastReportedFailureByStage = [:]
            self.didCompleteStartup = false
            self.scanProgressContinuation?.finish()
            self.scanProgressContinuation = nil
            self._scanProgressStream = nil
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
            snapshot = try snapshotDiffer.buildMetadataSnapshot(
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

        guard let exclusionMatcher else {
            return
        }

        let source = makeEventSource(includeSubfolders)
        eventSource = source
        source.start(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: exclusionMatcher,
            queue: queue
        ) { [weak self] changedDirectoryURLs in
            self?.scheduleVerification(changedDirectoryURLs: changedDirectoryURLs)
        }

        let safetyInterval = source.recommendedSafetyPollingInterval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + safetyInterval, repeating: safetyInterval)
        timer.setEventHandler { [weak self] in
            self?.scheduleVerification(changedDirectoryURLs: nil)
        }
        safetyTimer = timer
        timer.resume()

        didCompleteStartup = true
        scheduleVerification(changedDirectoryURLs: nil)
        // populateContentPhase runs synchronously on `queue`, so the
        // verifyChanges work item scheduled above cannot execute until
        // content population is complete.
        populateContentPhase(startupSequence: startupSequence)
    }

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL] = []
    ) throws -> [URL] {
        try snapshotDiffer.markdownFiles(
            in: folderURL,
            includeSubfolders: includeSubfolders,
            excludedSubdirectoryURLs: excludedSubdirectoryURLs
        )
    }

    func cachedMarkdownFileURLs() -> [URL]? {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            guard didCompleteStartup else { return nil }
            return lastSnapshot.keys.sorted(by: { $0.path < $1.path })
        }
        return queue.sync {
            guard didCompleteStartup else { return nil }
            return lastSnapshot.keys.sorted(by: { $0.path < $1.path })
        }
    }

    var didCompleteStartupForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return didCompleteStartup
        }

        return queue.sync { didCompleteStartup }
    }

    var scanProgressStream: AsyncStream<ScanProgress> {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return _scanProgressStream ?? emptyFinishedStream()
        }
        return queue.sync { _scanProgressStream ?? emptyFinishedStream() }
    }

    private func emptyFinishedStream() -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    private func populateContentPhase(startupSequence: UInt64) {
        let urls = Array(lastSnapshot.keys)
        let total = urls.count

        if total == 0 {
            scanProgressContinuation?.yield(ScanProgress(completed: 0, total: 0))
            scanProgressContinuation?.finish()
            scanProgressContinuation = nil
            return
        }

        let signpostID = Self.signposter.makeSignpostID()
        let intervalState = Self.signposter.beginInterval("populateContentPhase", id: signpostID)
        Self.signposter.emitEvent("contentScanStart", "files \(total)")

        var completed = 0
        var lastYieldTime = CFAbsoluteTimeGetCurrent()

        for url in urls {
            guard startupSequence == self.startupSequence else {
                scanProgressContinuation?.finish()
                scanProgressContinuation = nil
                return
            }

            if let existing = lastSnapshot[url], existing.markdown == nil {
                lastSnapshot[url] = existing.withContent(from: url)
            }
            completed += 1

            let now = CFAbsoluteTimeGetCurrent()
            let isLast = completed == total
            if isLast || (now - lastYieldTime) >= 0.25 {
                scanProgressContinuation?.yield(ScanProgress(completed: completed, total: total))
                lastYieldTime = now
            }
        }

        Self.signposter.endInterval("populateContentPhase", intervalState)
        Self.signposter.emitEvent("contentScanEnd", "files \(total)")

        scanProgressContinuation?.finish()
        scanProgressContinuation = nil
    }

    private func scheduleVerification(changedDirectoryURLs: Set<URL>?) {
        guard pendingWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingWorkItem = nil
            self?.verifyChanges(changedDirectoryURLs: changedDirectoryURLs)
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + verificationDelay, execute: workItem)
    }

    private func verifyChanges(changedDirectoryURLs: Set<URL>?) {
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

        let currentSnapshot: [URL: FolderFileSnapshot]
        do {
            let snapshotIntervalState = Self.signposter.beginInterval("buildIncrementalSnapshot", id: verifySignpostID)
            defer {
                Self.signposter.endInterval("buildIncrementalSnapshot", snapshotIntervalState)
            }

            if let changedDirectoryURLs, !changedDirectoryURLs.isEmpty {
                currentSnapshot = try snapshotDiffer.buildTargetedIncrementalSnapshot(
                    folderURL: watchedFolderURL,
                    includeSubfolders: includesSubfolders,
                    exclusionMatcher: exclusionMatcher,
                    previousSnapshot: lastSnapshot,
                    changedDirectoryURLs: changedDirectoryURLs
                )
            } else {
                currentSnapshot = try snapshotDiffer.buildIncrementalSnapshot(
                    folderURL: watchedFolderURL,
                    includeSubfolders: includesSubfolders,
                    exclusionMatcher: exclusionMatcher,
                    previousSnapshot: lastSnapshot
                )
            }

            Self.signposter.emitEvent(
                "snapshotCounts",
                "current \(currentSnapshot.count) previous \(self.lastSnapshot.count) include_subfolders \(self.includesSubfolders ? 1 : 0)"
            )
            clearReportedFailure(for: .verificationSnapshot)
        } catch {
            reportFailure(stage: .verificationSnapshot, folderURL: watchedFolderURL, error: error)
            return
        }

        let diffIntervalState = Self.signposter.beginInterval("diffSnapshots", id: verifySignpostID)
        let changedEvents = snapshotDiffer.diff(current: currentSnapshot, previous: lastSnapshot)
        Self.signposter.endInterval("diffSnapshots", diffIntervalState)
        Self.signposter.emitEvent(
            "diffCounts",
            "changed \(changedEvents.count) current \(currentSnapshot.count)"
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
