import Foundation
import OSLog

final class DispatchSourceFolderEventSource: FolderEventSource, @unchecked Sendable {
    private static let adaptiveSafetyPollingIdleCyclesPerStep = 3
    private static let adaptiveSafetyPollingMaximumMultiplier = 4
    private static let adaptiveSafetyPollingMaximumUnsignaledSkips = 2
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "DispatchSourceFolderEventSource"
    )

    private let pollingInterval: DispatchTimeInterval
    private let fallbackPollingInterval: DispatchTimeInterval
    private let recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval
    private let maximumDirectoryEventSourceCount: Int

    private var queue: DispatchQueue?
    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var timer: DispatchSourceTimer?
    private var timerInterval: DispatchTimeInterval?
    private var onEvent: ((@Sendable (Set<URL>?) -> Void))?
    private var usesEventSource = false
    private var needsDirectorySourceResync = false
    private var includesSubfolders = false
    private var watchedFolderURL: URL?
    private var exclusionMatcher: FolderWatchExclusionMatcher?
    private var adaptiveSafetyPollingMultiplier = 1
    private var adaptiveSafetyPollingIdleCycles = 0
    private var unsignaledVerificationSkipCycles = 0
    private var hasPendingFileSystemSignal = false

    var recommendedSafetyPollingInterval: DispatchTimeInterval {
        fallbackPollingInterval
    }

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval = .seconds(
            ReaderFolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
        ),
        maximumDirectoryEventSourceCount: Int = 128
    ) {
        self.pollingInterval = pollingInterval
        self.fallbackPollingInterval = fallbackPollingInterval
        self.recursiveEventSourceSafetyPollingInterval = recursiveEventSourceSafetyPollingInterval
        self.maximumDirectoryEventSourceCount = max(1, maximumDirectoryEventSourceCount)
    }

    deinit {
        stop()
    }

    // MARK: - FolderEventSource

    func start(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher,
        queue: DispatchQueue,
        onEvent: @escaping @Sendable (Set<URL>?) -> Void
    ) {
        let startWork = {
            self.stopInternal()

            self.queue = queue
            self.watchedFolderURL = folderURL
            self.includesSubfolders = includeSubfolders
            self.exclusionMatcher = exclusionMatcher
            self.onEvent = onEvent
            self.hasPendingFileSystemSignal = true

            self.synchronizeDirectorySources(
                folderURL: folderURL,
                includeSubfolders: includeSubfolders,
                exclusionMatcher: exclusionMatcher
            )
            self.needsDirectorySourceResync = false
            self.reconfigureTimerIfNeeded()
        }

        if let existingQueue = self.queue,
           DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            _ = existingQueue
            startWork()
        } else {
            queue.setSpecific(key: Self.queueKey, value: 1)
            queue.sync(execute: startWork)
        }
    }

    func stop() {
        if let queue,
           DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            _ = queue
            stopInternal()
        } else if let queue {
            queue.sync { self.stopInternal() }
        } else {
            stopInternal()
        }
    }

    // MARK: - Watcher integration

    func reportVerificationResult(
        changedEventCount: Int,
        didResynchronizeDirectories: Bool
    ) {
        adaptRecursiveEventSourceSafetyPollingIfNeeded(
            changedEventCount: changedEventCount,
            didResynchronizeDirectories: didResynchronizeDirectories
        )
    }

    func shouldSkipVerification() -> Bool {
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

    func consumePendingSignal() {
        hasPendingFileSystemSignal = false
        unsignaledVerificationSkipCycles = 0
    }

    func resynchronizeIfNeeded(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) -> Bool {
        guard needsDirectorySourceResync else {
            return false
        }

        synchronizeDirectorySources(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: exclusionMatcher
        )
        needsDirectorySourceResync = false
        return true
    }

    // MARK: - Testing properties

    var isUsingEventSourcesForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return usesEventSource
        }

        if let queue {
            return queue.sync { usesEventSource }
        }

        return usesEventSource
    }

    var activeDirectorySourceCountForTesting: Int {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return directorySources.count
        }

        if let queue {
            return queue.sync { directorySources.count }
        }

        return directorySources.count
    }

    var isUsingFallbackPollingIntervalForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval == fallbackPollingInterval
        }

        if let queue {
            return queue.sync { timerInterval == fallbackPollingInterval }
        }

        return timerInterval == fallbackPollingInterval
    }

    var isUsingRecursiveEventSourceSafetyPollingIntervalForTesting: Bool {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval == resolvedRecursiveEventSourceSafetyPollingInterval()
        }

        if let queue {
            return queue.sync { timerInterval == resolvedRecursiveEventSourceSafetyPollingInterval() }
        }

        return timerInterval == resolvedRecursiveEventSourceSafetyPollingInterval()
    }

    var currentTimerIntervalForTesting: DispatchTimeInterval? {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return timerInterval
        }

        if let queue {
            return queue.sync { timerInterval }
        }

        return timerInterval
    }

    // MARK: - Private

    private func stopInternal() {
        cancelAllDirectorySources()

        timer?.cancel()
        timer = nil
        timerInterval = nil

        watchedFolderURL = nil
        includesSubfolders = false
        exclusionMatcher = nil
        onEvent = nil
        usesEventSource = false
        needsDirectorySourceResync = false
        adaptiveSafetyPollingMultiplier = 1
        adaptiveSafetyPollingIdleCycles = 0
        unsignaledVerificationSkipCycles = 0
        hasPendingFileSystemSignal = false
    }

    private func synchronizeDirectorySources(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) {
        let usedEventSourcesBeforeSync = usesEventSource

        let watchedDirectoryURLs: [URL]
        do {
            watchedDirectoryURLs = try enumerateWatchedDirectories(
                folderURL: folderURL,
                includeSubfolders: includeSubfolders,
                exclusionMatcher: exclusionMatcher
            )
        } catch {
            watchedDirectoryURLs = [folderURL]
            Self.logger.error(
                "directory enumeration failed: \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
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
        if usedEventSourcesBeforeSync != usesEventSource {
            reconfigureTimerIfNeeded()
        }
    }

    private func reconfigureTimerIfNeeded() {
        guard let queue else {
            return
        }

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

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + desiredInterval, repeating: desiredInterval)
        newTimer.setEventHandler { [weak self] in
            self?.onEvent?(nil)
        }
        self.timer = newTimer
        timerInterval = desiredInterval
        newTimer.resume()
    }

    private func makeDirectorySource(for directoryURL: URL) -> DispatchSourceFileSystemObject? {
        guard let queue else {
            return nil
        }

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
            self.onEvent?(nil)
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
            if FolderSnapshotDiffer.shouldSkipEntryBeyondIncludeSubfolderDepth(
                normalizedDirectoryURL,
                rootFolderPathWithSlash: rootFolderPathWithSlash,
                enumerator: enumerator
            ) {
                continue
            }

            if FolderSnapshotDiffer.shouldSkipDescendants(
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
}
