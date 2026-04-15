import Combine
import Foundation

struct FolderWatchDirectoryScanSummary: Equatable {
    let subdirectoryCount: Int
    let markdownFileCount: Int
}

struct FolderWatchDirectoryScanProgress: Equatable {
    let scannedDirectoryCount: Int
    let estimatedTotalDirectoryCount: Int

    var fractionCompleted: Double {
        guard estimatedTotalDirectoryCount > 0 else {
            return 0
        }

        let progress = Double(scannedDirectoryCount) / Double(estimatedTotalDirectoryCount)
        return max(0, min(progress, 1))
    }
}

struct FolderWatchDirectoryNode: Identifiable, Equatable, Sendable {
    let path: String
    let name: String
    var children: [FolderWatchDirectoryNode]
    var subdirectoryCount: Int
    var markdownFileCount: Int

    var id: String { path }
}

final class FolderWatchDirectoryScanModel: ObservableObject {
    nonisolated private enum ScanLimit {
        static let maximumTraversalDepth = ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth
        static let maximumVisitedDirectories = 20_000
        static let maximumSupportedSubdirectoryCount = ReaderFolderWatchPerformancePolicy.maximumSupportedSubdirectoryCount
        static let cacheableSubdirectoryThreshold = 2_000
    }

    @Published private(set) var isLoading = false
    @Published private(set) var scanProgress: FolderWatchDirectoryScanProgress?
    @Published private(set) var didExceedSupportedSubdirectoryLimit = false
    @Published private(set) var rootNode: FolderWatchDirectoryNode?
    @Published private(set) var allSubdirectoryPaths: [String] = []
    @Published private(set) var summary: FolderWatchDirectoryScanSummary?

    private var activeTask: Task<Void, Never>?
    private static let cache = FolderWatchDirectoryScanCache()

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        scanProgress = nil
        didExceedSupportedSubdirectoryLimit = false
        rootNode = nil
        allSubdirectoryPaths = []
        summary = nil
    }

    func scan(folderURL: URL) {
        activeTask?.cancel()
        isLoading = true
        scanProgress = FolderWatchDirectoryScanProgress(
            scannedDirectoryCount: 0,
            estimatedTotalDirectoryCount: ScanLimit.maximumVisitedDirectories
        )
        didExceedSupportedSubdirectoryLimit = false
        rootNode = nil
        allSubdirectoryPaths = []
        summary = nil

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let cacheKey = Self.cacheKey(for: normalizedFolderURL)
        activeTask = Task {
            if let cacheKey,
               let cachedResult = await Self.cache.cachedResult(for: cacheKey) {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run { [weak self] in
                    self?.applyScanResult(cachedResult)
                }
                return
            }

            let result = await Task.detached(priority: .utility) {
                Self.buildTree(at: normalizedFolderURL) { scannedDirectoryCount in
                    guard scannedDirectoryCount == 1 || scannedDirectoryCount.isMultiple(of: 32) else {
                        return
                    }

                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.isLoading else {
                            return
                        }

                        self.scanProgress = FolderWatchDirectoryScanProgress(
                            scannedDirectoryCount: scannedDirectoryCount,
                            estimatedTotalDirectoryCount: ScanLimit.maximumVisitedDirectories
                        )
                    }
                }
            }.value

            guard !Task.isCancelled else {
                return
            }

            if let cacheKey,
               Self.shouldCache(result: result) {
                await Self.cache.store(result, for: cacheKey)
            }

            await MainActor.run { [weak self] in
                self?.applyScanResult(result)
            }
        }
    }

    @MainActor
    private func applyScanResult(_ result: FolderWatchDirectoryScanResult) {
        isLoading = false
        scanProgress = nil
        didExceedSupportedSubdirectoryLimit = result.didExceedSupportedSubdirectoryLimit

        if result.didExceedSupportedSubdirectoryLimit {
            rootNode = nil
            allSubdirectoryPaths = []
            summary = nil
            return
        }

        rootNode = result.rootNode
        allSubdirectoryPaths = result.allSubdirectoryPaths

        if let rootNode {
            summary = FolderWatchDirectoryScanSummary(
                subdirectoryCount: rootNode.subdirectoryCount,
                markdownFileCount: rootNode.markdownFileCount
            )
        } else {
            summary = nil
        }
    }

    nonisolated private static func buildTree(
        at folderURL: URL,
        onDirectoryScanned: @escaping @Sendable (Int) -> Void
    ) -> FolderWatchDirectoryScanResult {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard (try? normalizedFolderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return FolderWatchDirectoryScanResult(
                rootNode: nil,
                allSubdirectoryPaths: [],
                didExceedSupportedSubdirectoryLimit: false
            )
        }

        var scanState = DirectoryScanTraversalState()
        var visitedDirectoryPaths = Set<String>()
        let rootNode = buildNode(
            at: normalizedFolderURL,
            depth: 0,
            visitedDirectoryPaths: &visitedDirectoryPaths,
            scanState: &scanState,
            onDirectoryScanned: onDirectoryScanned
        )

        return FolderWatchDirectoryScanResult(
            rootNode: rootNode,
            allSubdirectoryPaths: rootNode?.children.flatMap { collectPaths(from: $0) }.sorted() ?? [],
            didExceedSupportedSubdirectoryLimit: scanState.didExceedSupportedSubdirectoryLimit
        )
    }

    nonisolated private static func collectPaths(from node: FolderWatchDirectoryNode) -> [String] {
        [node.path] + node.children.flatMap { collectPaths(from: $0) }
    }

    nonisolated private static func shouldCache(result: FolderWatchDirectoryScanResult) -> Bool {
        guard !result.didExceedSupportedSubdirectoryLimit,
              let rootNode = result.rootNode else {
            return false
        }

        return rootNode.subdirectoryCount <= ScanLimit.cacheableSubdirectoryThreshold
    }

    nonisolated private static func cacheKey(for normalizedFolderURL: URL) -> FolderWatchDirectoryScanCacheKey? {
        let values = try? normalizedFolderURL.resourceValues(
            forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        )

        guard values?.isDirectory == true else {
            return nil
        }

        let resourceIdentifier = values?.fileResourceIdentifier.map(String.init(describing:)) ?? "none"
        let contentModificationStamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fingerprint = "\(resourceIdentifier)|\(Int64(contentModificationStamp * 1_000))"

        return FolderWatchDirectoryScanCacheKey(folderPath: normalizedFolderURL.path, folderFingerprint: fingerprint)
    }

    nonisolated private static func buildNode(
        at directoryURL: URL,
        depth: Int,
        visitedDirectoryPaths: inout Set<String>,
        scanState: inout DirectoryScanTraversalState,
        onDirectoryScanned: @escaping @Sendable (Int) -> Void
    ) -> FolderWatchDirectoryNode? {
        guard !scanState.didExceedSupportedSubdirectoryLimit else {
            return nil
        }

        guard depth <= ScanLimit.maximumTraversalDepth else {
            return nil
        }

        let normalizedDirectoryURL = ReaderFileRouting.normalizedFileURL(directoryURL)
        let normalizedDirectoryPath = normalizedDirectoryURL.path

        guard visitedDirectoryPaths.count < ScanLimit.maximumVisitedDirectories else {
            return nil
        }

        guard visitedDirectoryPaths.insert(normalizedDirectoryPath).inserted else {
            return nil
        }

        let scannedSubdirectoryCount = max(0, visitedDirectoryPaths.count - 1)
        onDirectoryScanned(scannedSubdirectoryCount)

        if scannedSubdirectoryCount > ScanLimit.maximumSupportedSubdirectoryCount {
            scanState.didExceedSupportedSubdirectoryLimit = true
            return nil
        }

        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(
            at: normalizedDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return nil
        }

        var childDirectories: [FolderWatchDirectoryNode] = []
        var markdownCount = 0

        for entry in entries {
            guard !scanState.didExceedSupportedSubdirectoryLimit else {
                return nil
            }

            let normalizedEntry = ReaderFileRouting.normalizedFileURL(entry)
            let values = try? normalizedEntry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])

            if values?.isSymbolicLink == true {
                continue
            }

            if values?.isDirectory == true {
                if let childNode = buildNode(
                    at: normalizedEntry,
                    depth: depth + 1,
                    visitedDirectoryPaths: &visitedDirectoryPaths,
                    scanState: &scanState,
                    onDirectoryScanned: onDirectoryScanned
                ) {
                    childDirectories.append(childNode)
                    markdownCount += childNode.markdownFileCount
                }
                continue
            }

            if values?.isRegularFile == true,
               ReaderFileRouting.isSupportedMarkdownFileURL(normalizedEntry) {
                markdownCount += 1
            }
        }

        childDirectories.sort(by: { $0.path < $1.path })
        let descendantSubdirectoryCount = childDirectories.reduce(0) { $0 + 1 + $1.subdirectoryCount }
        let name = normalizedDirectoryURL.lastPathComponent.isEmpty ? normalizedDirectoryURL.path : normalizedDirectoryURL.lastPathComponent

        return FolderWatchDirectoryNode(
            path: normalizedDirectoryURL.path,
            name: name,
            children: childDirectories,
            subdirectoryCount: descendantSubdirectoryCount,
            markdownFileCount: markdownCount
        )
    }
}

struct FolderWatchDirectoryScanResult: Sendable {
    let rootNode: FolderWatchDirectoryNode?
    let allSubdirectoryPaths: [String]
    let didExceedSupportedSubdirectoryLimit: Bool
}

nonisolated struct DirectoryScanTraversalState: Sendable {
    var didExceedSupportedSubdirectoryLimit = false
}

