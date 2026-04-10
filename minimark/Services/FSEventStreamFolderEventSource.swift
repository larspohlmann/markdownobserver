import CoreServices
import Foundation
import OSLog

final class FSEventStreamFolderEventSource: FolderEventSource, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "FSEventStreamFolderEventSource"
    )

    private let latency: CFTimeInterval
    private let safetyPollingInterval: DispatchTimeInterval

    private var stream: FSEventStreamRef?
    private var timer: DispatchSourceTimer?
    private var queue: DispatchQueue?
    private var exclusionMatcher: FolderWatchExclusionMatcher?
    private var onEvent: ((@Sendable (Set<URL>?) -> Void))?

    init(
        latency: CFTimeInterval = 0.3,
        safetyPollingInterval: DispatchTimeInterval = .seconds(30)
    ) {
        self.latency = latency
        self.safetyPollingInterval = safetyPollingInterval
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
        stop()

        self.queue = queue
        self.exclusionMatcher = exclusionMatcher
        self.onEvent = onEvent

        let pathToWatch = folderURL.path as CFString
        let pathsToWatch = [pathToWatch] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let newStream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            Self.logger.error("failed to create FSEventStream for \(folderURL.path, privacy: .private(mask: .hash))")
            return
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        guard FSEventStreamStart(newStream) else {
            Self.logger.error("failed to start FSEventStream for \(folderURL.path, privacy: .private(mask: .hash))")
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return
        }

        stream = newStream
        configureSafetyTimer(queue: queue)
    }

    func stop() {
        timer?.cancel()
        timer = nil

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil

        queue = nil
        exclusionMatcher = nil
        onEvent = nil
    }

    // MARK: - Private

    private func configureSafetyTimer(queue: DispatchQueue) {
        timer?.cancel()

        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(
            deadline: .now() + safetyPollingInterval,
            repeating: safetyPollingInterval
        )
        newTimer.setEventHandler { [weak self] in
            self?.onEvent?(nil)
        }
        timer = newTimer
        newTimer.resume()
    }

    fileprivate func handleEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        eventIds: UnsafePointer<FSEventStreamEventId>
    ) {
        guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray?.self) else {
            onEvent?(nil)
            return
        }

        var changedDirectoryURLs = Set<URL>()
        var requiresFullScan = false

        for index in 0..<numEvents {
            let flags = eventFlags[index]

            if (flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs)) != 0 ||
               (flags & UInt32(kFSEventStreamEventFlagRootChanged)) != 0 {
                requiresFullScan = true
                break
            }

            guard let cfPath = CFArrayGetValueAtIndex(cfPaths, index) else {
                continue
            }

            let path = unsafeBitCast(cfPath, to: CFString.self) as String

            if let exclusionMatcher, exclusionMatcher.excludesNormalizedFilePath(path) {
                continue
            }

            let directoryURL: URL
            let isDirectory = (flags & UInt32(kFSEventStreamEventFlagItemIsDir)) != 0

            if isDirectory {
                directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            } else {
                let parentPath = (path as NSString).deletingLastPathComponent
                directoryURL = URL(fileURLWithPath: parentPath, isDirectory: true)
            }

            changedDirectoryURLs.insert(
                ReaderFileRouting.normalizedFileURL(directoryURL)
            )
        }

        if requiresFullScan {
            onEvent?(nil)
        } else if !changedDirectoryURLs.isEmpty {
            onEvent?(changedDirectoryURLs)
        }
    }
}

// MARK: - FSEventStream C callback

private func fsEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else {
        return
    }

    let source = Unmanaged<FSEventStreamFolderEventSource>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()

    source.handleEvents(
        numEvents: numEvents,
        eventPaths: eventPaths,
        eventFlags: eventFlags,
        eventIds: eventIds
    )
}
