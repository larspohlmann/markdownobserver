import Combine
import Foundation

struct FileSelectionNode: Identifiable, Equatable {
    let path: String
    let name: String
    let isDirectory: Bool
    let fileURL: URL?
    var children: [FileSelectionNode]
    var markdownFileCount: Int

    var id: String { path }

    var allFileURLs: [URL] {
        if let fileURL {
            return [fileURL]
        }
        return children.flatMap(\.allFileURLs)
    }
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
        self.folderURL = folderURL
        self.allFileURLs = fileURLs
        self.selectedFileURLs = Set(fileURLs)
        self.rootNodes = Self.buildTree(folderURL: folderURL, fileURLs: fileURLs)
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

    func allFilesInNode(_ node: FileSelectionNode) -> [URL] {
        node.allFileURLs
    }

    func isNodeFullySelected(_ node: FileSelectionNode) -> Bool {
        let nodeFiles = node.allFileURLs
        guard !nodeFiles.isEmpty else { return false }
        return nodeFiles.allSatisfy { selectedFileURLs.contains($0) }
    }

    func isNodePartiallySelected(_ node: FileSelectionNode) -> Bool {
        let nodeFiles = node.allFileURLs
        guard !nodeFiles.isEmpty else { return false }
        let selectedInNode = nodeFiles.filter { selectedFileURLs.contains($0) }
        return !selectedInNode.isEmpty && selectedInNode.count < nodeFiles.count
    }

    func toggleFolder(_ node: FileSelectionNode) {
        let nodeFiles = node.allFileURLs
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
        let normalizedFolderPath = ReaderFileRouting.normalizedFileURL(folderURL).path
        let folderPathPrefix = normalizedFolderPath.hasSuffix("/")
            ? normalizedFolderPath
            : normalizedFolderPath + "/"

        struct IntermediateDirectory {
            var files: [URL] = []
            var subdirectories: Set<String> = []
        }

        var directoriesByPath: [String: IntermediateDirectory] = [:]

        for fileURL in fileURLs {
            let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
            let filePath = normalizedFileURL.path
            let directoryPath = normalizedFileURL.deletingLastPathComponent().path

            directoriesByPath[directoryPath, default: IntermediateDirectory()].files.append(normalizedFileURL)

            // Register intermediate directories up to the root
            var currentPath = directoryPath
            while currentPath.hasPrefix(folderPathPrefix), currentPath != normalizedFolderPath {
                let parentPath = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
                let normalizedParent = parentPath.hasSuffix("/") && parentPath.count > 1
                    ? String(parentPath.dropLast())
                    : parentPath
                directoriesByPath[normalizedParent, default: IntermediateDirectory()].subdirectories.insert(currentPath)
                currentPath = normalizedParent
            }
        }

        func buildNode(directoryPath: String) -> FileSelectionNode {
            let info = directoriesByPath[directoryPath] ?? IntermediateDirectory()
            let directoryName = URL(fileURLWithPath: directoryPath).lastPathComponent

            var children: [FileSelectionNode] = []

            // Add subdirectory nodes
            let sortedSubdirs = info.subdirectories.sorted()
            for subdirPath in sortedSubdirs {
                children.append(buildNode(directoryPath: subdirPath))
            }

            // Add file nodes
            let sortedFiles = info.files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            for fileURL in sortedFiles {
                children.append(FileSelectionNode(
                    path: fileURL.path,
                    name: fileURL.lastPathComponent,
                    isDirectory: false,
                    fileURL: fileURL,
                    children: [],
                    markdownFileCount: 1
                ))
            }

            let totalFileCount = children.reduce(0) { $0 + $1.markdownFileCount }

            return FileSelectionNode(
                path: directoryPath,
                name: directoryName,
                isDirectory: true,
                fileURL: nil,
                children: children,
                markdownFileCount: totalFileCount
            )
        }

        let rootInfo = directoriesByPath[normalizedFolderPath] ?? IntermediateDirectory()
        var rootChildren: [FileSelectionNode] = []

        // Add subdirectory nodes at root level
        let sortedSubdirs = rootInfo.subdirectories.sorted()
        for subdirPath in sortedSubdirs {
            rootChildren.append(buildNode(directoryPath: subdirPath))
        }

        // Add file nodes at root level
        let sortedFiles = rootInfo.files.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        for fileURL in sortedFiles {
            rootChildren.append(FileSelectionNode(
                path: fileURL.path,
                name: fileURL.lastPathComponent,
                isDirectory: false,
                fileURL: fileURL,
                children: [],
                markdownFileCount: 1
            ))
        }

        return rootChildren
    }
}
