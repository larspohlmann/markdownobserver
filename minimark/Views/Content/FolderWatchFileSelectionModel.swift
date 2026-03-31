import Combine
import Foundation

struct FileSelectionNode: Identifiable, Equatable {
    let path: String
    let name: String
    let isDirectory: Bool
    let fileURL: URL?
    var children: [FileSelectionNode]
    var markdownFileCount: Int
    let cachedFileURLs: [URL]

    var id: String { path }
}

@MainActor
final class FolderWatchFileSelectionModel: ObservableObject {
    let folderURL: URL
    @Published var selectedFileURLs: Set<URL>
    @Published private(set) var rootNodes: [FileSelectionNode] = []
    @Published private(set) var allFileURLs: [URL] = []

    var selectedCount: Int {
        selectedFileURLs.count
    }

    var totalCount: Int {
        allFileURLs.count
    }

    var exceedsPerformanceThreshold: Bool {
        selectedFileURLs.count > ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount
    }

    init(folderURL: URL, fileURLs: [URL]) {
        let normalizedFolder = ReaderFileRouting.normalizedFileURL(folderURL)
        let normalizedFiles = fileURLs.map { ReaderFileRouting.normalizedFileURL($0) }
        self.folderURL = normalizedFolder
        self.allFileURLs = normalizedFiles
        self.selectedFileURLs = Set(normalizedFiles)
        self.rootNodes = Self.buildTree(folderURL: normalizedFolder, fileURLs: normalizedFiles)
    }

    func selectAll() {
        selectedFileURLs = Set(allFileURLs)
    }

    func clearAll() {
        selectedFileURLs.removeAll()
    }

    func isSelected(_ fileURL: URL) -> Bool {
        selectedFileURLs.contains(fileURL)
    }

    func toggleFile(_ fileURL: URL) {
        if selectedFileURLs.contains(fileURL) {
            selectedFileURLs.remove(fileURL)
        } else {
            selectedFileURLs.insert(fileURL)
        }
    }

    func isNodeFullySelected(_ node: FileSelectionNode) -> Bool {
        let nodeFiles = node.cachedFileURLs
        guard !nodeFiles.isEmpty else { return false }
        return nodeFiles.allSatisfy { selectedFileURLs.contains($0) }
    }

    func isNodePartiallySelected(_ node: FileSelectionNode) -> Bool {
        let nodeFiles = node.cachedFileURLs
        guard !nodeFiles.isEmpty else { return false }
        var found = false
        var foundAll = true
        for url in nodeFiles {
            if selectedFileURLs.contains(url) { found = true }
            else { foundAll = false }
            if found && !foundAll { return true }
        }
        return false
    }

    func toggleFolder(_ node: FileSelectionNode) {
        let nodeFiles = node.cachedFileURLs
        if isNodeFullySelected(node) {
            for fileURL in nodeFiles {
                selectedFileURLs.remove(fileURL)
            }
        } else {
            for fileURL in nodeFiles {
                selectedFileURLs.insert(fileURL)
            }
        }
    }

    private static func buildTree(folderURL: URL, fileURLs: [URL]) -> [FileSelectionNode] {
        let normalizedFolderPath = folderURL.path
        let folderPathPrefix = normalizedFolderPath.hasSuffix("/")
            ? normalizedFolderPath
            : normalizedFolderPath + "/"

        struct IntermediateDirectory {
            var files: [URL] = []
            var subdirectories: Set<String> = []
        }

        var directoriesByPath: [String: IntermediateDirectory] = [:]

        for fileURL in fileURLs {
            let directoryPath = fileURL.deletingLastPathComponent().path

            directoriesByPath[directoryPath, default: IntermediateDirectory()].files.append(fileURL)

            var currentPath = directoryPath
            while currentPath.hasPrefix(folderPathPrefix), currentPath != normalizedFolderPath {
                let parentPath = (currentPath as NSString).deletingLastPathComponent
                directoriesByPath[parentPath, default: IntermediateDirectory()].subdirectories.insert(currentPath)
                currentPath = parentPath
            }
        }

        func buildNode(directoryPath: String) -> FileSelectionNode {
            let info = directoriesByPath[directoryPath] ?? IntermediateDirectory()
            let directoryName = (directoryPath as NSString).lastPathComponent

            var children: [FileSelectionNode] = []

            for subdirPath in info.subdirectories.sorted() {
                children.append(buildNode(directoryPath: subdirPath))
            }

            let sortedFiles = info.files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            for fileURL in sortedFiles {
                children.append(FileSelectionNode(
                    path: fileURL.path,
                    name: fileURL.lastPathComponent,
                    isDirectory: false,
                    fileURL: fileURL,
                    children: [],
                    markdownFileCount: 1,
                    cachedFileURLs: [fileURL]
                ))
            }

            let totalFileCount = children.reduce(0) { $0 + $1.markdownFileCount }
            let allCachedURLs = children.flatMap(\.cachedFileURLs)

            return FileSelectionNode(
                path: directoryPath,
                name: directoryName,
                isDirectory: true,
                fileURL: nil,
                children: children,
                markdownFileCount: totalFileCount,
                cachedFileURLs: allCachedURLs
            )
        }

        return buildNode(directoryPath: normalizedFolderPath).children
    }
}
