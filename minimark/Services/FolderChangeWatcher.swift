import Foundation

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

protocol FolderChangeWatching: AnyObject {
    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws

    func stopWatching()

    func markdownFiles(in folderURL: URL, includeSubfolders: Bool) throws -> [URL]
}

final class FolderChangeWatcher: FolderChangeWatching {
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "minimark.folderwatcher")
    private let pollingInterval: DispatchTimeInterval
    private let fallbackPollingInterval: DispatchTimeInterval
    private let verificationDelay: DispatchTimeInterval
    private let maximumDirectoryEventSourceCount: Int
    private var directorySources: [URL: DispatchSourceFileSystemObject] = [:]
    private var timer: DispatchSourceTimer?
    private var timerInterval: DispatchTimeInterval?
    private var pendingWorkItem: DispatchWorkItem?
    private var usesEventSource = false

    private var watchedFolderURL: URL?
    private var includesSubfolders = false
    private var onMarkdownFilesAddedOrChanged: (([ReaderFolderWatchChangeEvent]) -> Void)?
    private var lastSnapshot: [URL: FolderFileSnapshot] = [:]

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        verificationDelay: DispatchTimeInterval = .milliseconds(75)
    ) {
        self.pollingInterval = pollingInterval
        self.fallbackPollingInterval = fallbackPollingInterval
        self.verificationDelay = verificationDelay
        self.maximumDirectoryEventSourceCount = 128
        queue.setSpecific(key: Self.queueKey, value: 1)
    }

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        verificationDelay: DispatchTimeInterval = .milliseconds(75),
        maximumDirectoryEventSourceCount: Int = 128
    ) {
        self.pollingInterval = pollingInterval
        self.fallbackPollingInterval = fallbackPollingInterval
        self.verificationDelay = verificationDelay
        self.maximumDirectoryEventSourceCount = max(1, maximumDirectoryEventSourceCount)
        queue.setSpecific(key: Self.queueKey, value: 1)
    }

    deinit {
        stopWatching()
    }

    func startWatching(
        folderURL: URL,
        includeSubfolders: Bool,
        onMarkdownFilesAddedOrChanged: @escaping @Sendable ([ReaderFolderWatchChangeEvent]) -> Void
    ) throws {
        stopWatching()

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard normalizedFolderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        self.watchedFolderURL = normalizedFolderURL
        self.includesSubfolders = includeSubfolders
        self.onMarkdownFilesAddedOrChanged = onMarkdownFilesAddedOrChanged
        self.lastSnapshot = try buildSnapshot(folderURL: normalizedFolderURL, includeSubfolders: includeSubfolders)

        synchronizeDirectorySources(folderURL: normalizedFolderURL, includeSubfolders: includeSubfolders)
        reconfigureTimerIfNeeded()

        scheduleVerification()
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
            self.onMarkdownFilesAddedOrChanged = nil
            self.lastSnapshot = [:]
            self.usesEventSource = false
        }

        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopWork()
        } else {
            queue.sync(execute: stopWork)
        }
    }

    func markdownFiles(in folderURL: URL, includeSubfolders: Bool) throws -> [URL] {
        try enumerateMarkdownFiles(
            folderURL: ReaderFileRouting.normalizedFileURL(folderURL),
            includeSubfolders: includeSubfolders
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
        guard let watchedFolderURL, let onMarkdownFilesAddedOrChanged else {
            return
        }

        guard let currentSnapshot = try? buildIncrementalSnapshot(
            folderURL: watchedFolderURL,
            includeSubfolders: includesSubfolders,
            previousSnapshot: lastSnapshot
        ) else {
            return
        }

        synchronizeDirectorySources(folderURL: watchedFolderURL, includeSubfolders: includesSubfolders)

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

        lastSnapshot = currentSnapshot
        guard !changedEvents.isEmpty else {
            return
        }

        let normalized = changedEvents.sorted(by: { $0.fileURL.path < $1.fileURL.path })

        DispatchQueue.main.async {
            onMarkdownFilesAddedOrChanged(normalized)
        }
    }

    private func buildSnapshot(folderURL: URL, includeSubfolders: Bool) throws -> [URL: FolderFileSnapshot] {
        var snapshot: [URL: FolderFileSnapshot] = [:]
        let markdownURLs = try enumerateMarkdownFiles(folderURL: folderURL, includeSubfolders: includeSubfolders)

        for url in markdownURLs {
            snapshot[url] = FolderFileSnapshot(url: url)
        }

        return snapshot
    }

    private func synchronizeDirectorySources(folderURL: URL, includeSubfolders: Bool) {
        let usedEventSourcesBeforeSync = usesEventSource
        let watchedDirectoryURLs = (try? enumerateWatchedDirectories(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders
        )) ?? [folderURL]

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
        let desiredInterval = usesEventSource ? fallbackPollingInterval : pollingInterval
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
            self?.scheduleVerification()
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

    private func buildIncrementalSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        previousSnapshot: [URL: FolderFileSnapshot]
    ) throws -> [URL: FolderFileSnapshot] {
        let markdownURLs = try enumerateMarkdownFiles(folderURL: folderURL, includeSubfolders: includeSubfolders)
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

    private func enumerateMarkdownFiles(folderURL: URL, includeSubfolders: Bool) throws -> [URL] {
        guard folderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        let fileManager = FileManager.default

        if includeSubfolders {
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
                if let normalizedFileURL = regularMarkdownFileURL(from: fileURL) {
                    result.append(normalizedFileURL)
                }
            }

            return result
        } else {
            let urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )

            return urls.compactMap(regularMarkdownFileURL(from:))
        }
    }

    private func enumerateWatchedDirectories(folderURL: URL, includeSubfolders: Bool) throws -> [URL] {
        guard folderURL.isFileURL else {
            throw ReaderError.invalidFileURL
        }

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard includeSubfolders else {
            return [normalizedFolderURL]
        }

        var result: [URL] = [normalizedFolderURL]
        let fileManager = FileManager.default

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
            if (try? normalizedDirectoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result.append(normalizedDirectoryURL)
            }
        }

        return result
    }

    private func regularMarkdownFileURL(from fileURL: URL) -> URL? {
        guard ReaderFileRouting.isSupportedMarkdownFileURL(fileURL) else {
            return nil
        }

        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        let isRegularFile = (try? normalizedFileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
        guard isRegularFile else {
            return nil
        }

        return normalizedFileURL
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
