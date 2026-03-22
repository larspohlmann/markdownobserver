import Foundation

protocol FileChangeWatching: AnyObject {
    func startWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws
    func stopWatching()
}

final class FileChangeWatcher: FileChangeWatching {
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private let queue = DispatchQueue(label: "minimark.filewatcher")
    private let pollingInterval: DispatchTimeInterval
    private let fallbackPollingInterval: DispatchTimeInterval
    private let verificationDelay: DispatchTimeInterval
    private var directoryDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var fileURL: URL?
    private var onChange: (@Sendable () -> Void)?
    private var lastMetadata: FileMetadata?
    private var lastContentSignature: UInt64?
    private var pendingWorkItem: DispatchWorkItem?
    private var usesEventSource = false

    init(
        pollingInterval: DispatchTimeInterval = .seconds(1),
        fallbackPollingInterval: DispatchTimeInterval = .seconds(3),
        verificationDelay: DispatchTimeInterval = .milliseconds(60)
    ) {
        self.pollingInterval = pollingInterval
        self.fallbackPollingInterval = fallbackPollingInterval
        self.verificationDelay = verificationDelay
        queue.setSpecific(key: Self.queueKey, value: 1)
    }

    deinit {
        stopWatching()
    }

    func startWatching(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        stopWatching()

        self.fileURL = fileURL
        self.onChange = onChange
        self.lastMetadata = FileMetadata(url: fileURL)
        self.lastContentSignature = Self.makeContentSignature(for: fileURL)

        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        if descriptor >= 0 {
            self.directoryDescriptor = descriptor
            self.usesEventSource = true

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

            self.source = source
            source.resume()
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let timerInterval = usesEventSource ? fallbackPollingInterval : pollingInterval
        timer.schedule(deadline: .now() + timerInterval, repeating: timerInterval)
        timer.setEventHandler { [weak self] in
            self?.verifyFileChange(forceContentVerification: true)
        }
        self.timer = timer
        timer.resume()
    }

    func stopWatching() {
        let stopWork = {
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil

            self.source?.cancel()
            self.source = nil
            self.directoryDescriptor = -1

            self.timer?.cancel()
            self.timer = nil

            self.onChange = nil
            self.fileURL = nil
            self.lastMetadata = nil
            self.lastContentSignature = nil
            self.usesEventSource = false
        }

        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            stopWork()
        } else {
            queue.sync(execute: stopWork)
        }
    }

    private func scheduleVerification() {
        guard pendingWorkItem == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingWorkItem = nil
            self?.verifyFileChange(forceContentVerification: false)
        }
        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + verificationDelay, execute: workItem)
    }

    private func verifyFileChange(forceContentVerification: Bool) {
        guard let fileURL, let onChange else {
            return
        }

        let currentMetadata = FileMetadata(url: fileURL)
        let previousMetadata = lastMetadata

        if currentMetadata != previousMetadata {
            let currentContentSignature = currentMetadata.exists
                ? Self.makeContentSignature(for: fileURL)
                : nil

            lastMetadata = currentMetadata
            let shouldNotify = shouldNotifyMetadataChange(
                previousMetadata: previousMetadata,
                currentMetadata: currentMetadata,
                currentContentSignature: currentContentSignature
            )

            lastContentSignature = currentContentSignature

            guard shouldNotify else {
                return
            }

            DispatchQueue.main.async {
                onChange()
            }
            return
        }

        guard currentMetadata.exists, forceContentVerification else {
            return
        }

        let currentContentSignature = Self.makeContentSignature(for: fileURL)
        guard currentContentSignature != lastContentSignature else {
            return
        }

        lastContentSignature = currentContentSignature
        DispatchQueue.main.async {
            onChange()
        }
    }

    private func shouldNotifyMetadataChange(
        previousMetadata: FileMetadata?,
        currentMetadata: FileMetadata,
        currentContentSignature: UInt64?
    ) -> Bool {
        guard let previousMetadata else {
            return true
        }

        if previousMetadata.exists != currentMetadata.exists {
            return true
        }

        guard currentMetadata.exists else {
            return false
        }

        if previousMetadata.resourceIdentity != currentMetadata.resourceIdentity {
            return true
        }

        if previousMetadata.fileSize != currentMetadata.fileSize {
            return true
        }

        return currentContentSignature != lastContentSignature
    }

    private static func makeContentSignature(for url: URL) -> UInt64? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }

        var hash: UInt64 = 1469598103934665603
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

private struct FileMetadata: Equatable {
    let exists: Bool
    let fileSize: UInt64
    let modificationDate: Date
    let resourceIdentity: String

    init(url: URL) {
        let path = url.path
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let type = attributes[.type] as? FileAttributeType,
           type == .typeRegular {
            self.exists = true
            self.fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            self.modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast

            if let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value {
                self.resourceIdentity = String(inode)
            } else if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
                      let fileResourceIdentifier = values.fileResourceIdentifier {
                self.resourceIdentity = String(describing: fileResourceIdentifier)
            } else {
                self.resourceIdentity = "none"
            }
        } else {
            self.exists = false
            self.fileSize = 0
            self.modificationDate = .distantPast
            self.resourceIdentity = "missing"
        }
    }
}
