import Foundation
import OSLog

final class DispatchSourceFolderEventSource: FolderEventSource, @unchecked Sendable {
    private static let queueKey = DispatchSpecificKey<ObjectIdentifier>()
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

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        recursiveEventSourceSafetyPollingInterval: DispatchTimeInterval = .seconds(
            FolderWatchPerformancePolicy.recursiveEventSourceSafetyPollingIntervalSeconds
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

            self.synchronizeDirectorySources(
                folderURL: folderURL,
                includeSubfolders: includeSubfolders,
                exclusionMatcher: exclusionMatcher
            )
            self.needsDirectorySourceResync = false
            self.reconfigureTimerIfNeeded()
        }

        let token = ObjectIdentifier(self)
        queue.setSpecific(key: Self.queueKey, value: token)

        if DispatchQueue.getSpecific(key: Self.queueKey) == token {
            startWork()
        } else {
            queue.sync(execute: startWork)
        }
    }

    func stop() {
        if DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) {
            stopInternal()
        } else if let queue {
            queue.sync { self.stopInternal() }
        } else {
            stopInternal()
        }
    }

    // MARK: - Testing properties

    var isUsingEventSourcesForTesting: Bool { syncRead { usesEventSource } }
    var activeDirectorySourceCountForTesting: Int { syncRead { directorySources.count } }
    var isUsingFallbackPollingIntervalForTesting: Bool { syncRead { timerInterval == fallbackPollingInterval } }
    var isUsingRecursiveEventSourceSafetyPollingIntervalForTesting: Bool { syncRead { timerInterval == recursiveEventSourceSafetyPollingInterval } }
    var currentTimerIntervalForTesting: DispatchTimeInterval? { syncRead { timerInterval } }

    private func syncRead<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) {
            return body()
        }
        if let queue {
            return queue.sync(execute: body)
        }
        return body()
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
                ? recursiveEventSourceSafetyPollingInterval
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
            self.resynchronizeIfNeeded()
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

    private func resynchronizeIfNeeded() {
        guard needsDirectorySourceResync,
              let folderURL = watchedFolderURL,
              let exclusionMatcher else {
            return
        }
        synchronizeDirectorySources(
            folderURL: folderURL,
            includeSubfolders: includesSubfolders,
            exclusionMatcher: exclusionMatcher
        )
        needsDirectorySourceResync = false
    }

    private func handleDirectorySourceEvent(_ events: DispatchSource.FileSystemEvent) {
        let topologyChangeEvents: DispatchSource.FileSystemEvent = [.rename, .delete, .revoke, .write]
        if !events.intersection(topologyChangeEvents).isEmpty {
            needsDirectorySourceResync = needsDirectorySourceResync || includesSubfolders
        }
    }

    private func enumerateWatchedDirectories(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) throws -> [URL] {
        guard folderURL.isFileURL else {
            throw AppError.invalidFileURL
        }

        let normalizedFolderURL = FileRouting.normalizedFileURL(folderURL)
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
            let normalizedDirectoryURL = FileRouting.normalizedFileURL(directoryURL)
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
}
