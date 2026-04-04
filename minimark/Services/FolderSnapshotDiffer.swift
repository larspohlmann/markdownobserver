import Foundation
import OSLog

protocol FolderSnapshotDiffing: Sendable {
    func buildMetadataSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL: FolderFileSnapshot]

    func buildIncrementalSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher,
        previousSnapshot: [URL: FolderFileSnapshot]
    ) throws -> [URL: FolderFileSnapshot]

    func diff(
        current: [URL: FolderFileSnapshot],
        previous: [URL: FolderFileSnapshot]
    ) -> [ReaderFolderWatchChangeEvent]

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL]
}

struct FolderSnapshotDiffer: FolderSnapshotDiffing {
    fileprivate static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "FolderSnapshotDiffer"
    )

    func buildMetadataSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL: FolderFileSnapshot] {
        let markdownURLs = try enumerateMarkdownFiles(
            folderURL: folderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: FolderWatchExclusionMatcher(
                rootFolderURL: folderURL,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
        )

        var snapshot: [URL: FolderFileSnapshot] = [:]
        for url in markdownURLs {
            snapshot[url] = FolderFileSnapshot(metadata: FolderFileMetadata(url: url))
        }

        return snapshot
    }

    func buildIncrementalSnapshot(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher,
        previousSnapshot: [URL: FolderFileSnapshot]
    ) throws -> [URL: FolderFileSnapshot] {
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

    func diff(
        current: [URL: FolderFileSnapshot],
        previous: [URL: FolderFileSnapshot]
    ) -> [ReaderFolderWatchChangeEvent] {
        var changedEvents: [ReaderFolderWatchChangeEvent] = []
        for (url, currentFingerprint) in current {
            if let previousEntry = previous[url] {
                if previousEntry.hasMeaningfulModification(comparedTo: currentFingerprint) {
                    changedEvents.append(
                        ReaderFolderWatchChangeEvent(
                            fileURL: url,
                            kind: .modified,
                            previousMarkdown: previousEntry.markdown
                        )
                    )
                }
            } else {
                changedEvents.append(
                    ReaderFolderWatchChangeEvent(fileURL: url, kind: .added)
                )
            }
        }
        return changedEvents
    }

    func markdownFiles(
        in folderURL: URL,
        includeSubfolders: Bool,
        excludedSubdirectoryURLs: [URL]
    ) throws -> [URL] {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        return try enumerateMarkdownFiles(
            folderURL: normalizedFolderURL,
            includeSubfolders: includeSubfolders,
            exclusionMatcher: FolderWatchExclusionMatcher(
                rootFolderURL: normalizedFolderURL,
                excludedSubdirectoryURLs: excludedSubdirectoryURLs
            )
        ).sorted(by: { $0.path < $1.path })
    }

    // MARK: - Private helpers

    private func enumerateMarkdownFiles(
        folderURL: URL,
        includeSubfolders: Bool,
        exclusionMatcher: FolderWatchExclusionMatcher
    ) throws -> [URL] {
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
                if Self.shouldSkipEntryBeyondIncludeSubfolderDepth(
                    normalizedFileURL,
                    rootFolderPathWithSlash: rootFolderPathWithSlash,
                    enumerator: enumerator
                ) {
                    continue
                }

                if Self.shouldSkipDescendants(
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

            return result
        } else {
            let urls = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            )
            return urls
                .map(ReaderFileRouting.normalizedFileURL)
                .compactMap(regularMarkdownFileURL(fromNormalized:))
                .filter { !exclusionMatcher.excludesNormalizedFilePath($0.path) }
        }
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

    static func shouldSkipDescendants(
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

    static func shouldSkipEntryBeyondIncludeSubfolderDepth(
        _ normalizedURL: URL,
        rootFolderPathWithSlash: String,
        enumerator: FileManager.DirectoryEnumerator
    ) -> Bool {
        let isDirectory = (try? normalizedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let depth = Self.relativePathDepth(
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

    static func relativePathDepth(forPath path: String, relativeToPathWithSlash rootPathWithSlash: String, isDirectory: Bool) -> Int {
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
}

// MARK: - Snapshot types

struct FolderFileSnapshot: Equatable {
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
        if metadata.exists {
            do {
                markdown = try String(contentsOf: url, encoding: .utf8)
            } catch {
                FolderSnapshotDiffer.logger.error(
                    "snapshot read failed: \(error.localizedDescription, privacy: .public)"
                )
                markdown = nil
            }
        } else {
            markdown = nil
        }
    }

    init(metadata: FolderFileMetadata) {
        fileSize = metadata.fileSize
        modificationDate = metadata.modificationDate
        resourceIdentity = metadata.resourceIdentity
        markdown = nil
    }

    private init(fileSize: UInt64, modificationDate: Date, resourceIdentity: String, markdown: String?) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.resourceIdentity = resourceIdentity
        self.markdown = markdown
    }

    func withContent(from url: URL) -> FolderFileSnapshot {
        let content: String?
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            FolderSnapshotDiffer.logger.error(
                "snapshot content reload failed: \(error.localizedDescription, privacy: .public)"
            )
            content = nil
        }
        return FolderFileSnapshot(
            fileSize: fileSize,
            modificationDate: modificationDate,
            resourceIdentity: resourceIdentity,
            markdown: content
        )
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

struct FolderFileMetadata: Equatable {
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

// MARK: - Exclusion matcher

struct FolderWatchExclusionMatcher {
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
