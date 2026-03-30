import Testing
import Foundation
@testable import minimark

@Suite("FolderWatchFileSelectionModel")
struct FolderWatchFileSelectionModelTests {

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-selection-model-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test @MainActor func allFilesSelectedByDefault() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let files = (0..<5).map { folderURL.appendingPathComponent("file\($0).md") }
        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: files)

        #expect(model.selectedCount == 5)
        #expect(model.totalCount == 5)
        for file in files {
            #expect(model.isSelected(file))
        }
    }

    @Test @MainActor func toggleFileRemovesAndAddsSelection() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let files = (0..<3).map { folderURL.appendingPathComponent("file\($0).md") }
        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: files)

        model.toggleFile(files[1])
        #expect(!model.isSelected(files[1]))
        #expect(model.selectedCount == 2)

        model.toggleFile(files[1])
        #expect(model.isSelected(files[1]))
        #expect(model.selectedCount == 3)
    }

    @Test @MainActor func clearAllRemovesAllSelections() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let files = (0..<5).map { folderURL.appendingPathComponent("file\($0).md") }
        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: files)

        model.clearAll()
        #expect(model.selectedCount == 0)
        for file in files {
            #expect(!model.isSelected(file))
        }
    }

    @Test @MainActor func selectAllReselectsEverything() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let files = (0..<5).map { folderURL.appendingPathComponent("file\($0).md") }
        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: files)

        model.clearAll()
        model.selectAll()
        #expect(model.selectedCount == 5)
    }

    @Test @MainActor func performanceThresholdDetection() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let threshold = ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount
        let files = (0...threshold).map { folderURL.appendingPathComponent("file\($0).md") }
        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: files)

        #expect(model.exceedsPerformanceThreshold)

        // Deselect enough to go below threshold
        model.toggleFile(files[0])
        model.toggleFile(files[1])
        #expect(!model.exceedsPerformanceThreshold)
    }

    @Test @MainActor func treeGroupsFilesBySubdirectory() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let subA = folderURL.appendingPathComponent("subA", isDirectory: true)
        try? FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)

        let rootFile = folderURL.appendingPathComponent("root.md")
        let subFile1 = subA.appendingPathComponent("a1.md")
        let subFile2 = subA.appendingPathComponent("a2.md")

        let model = FolderWatchFileSelectionModel(
            folderURL: folderURL,
            fileURLs: [rootFile, subFile1, subFile2]
        )

        // Should have one directory node (subA) and one file node (root.md) at root level
        let directoryNodes = model.rootNodes.filter(\.isDirectory)
        let fileNodes = model.rootNodes.filter { !$0.isDirectory }

        #expect(directoryNodes.count == 1)
        #expect(fileNodes.count == 1)
        #expect(directoryNodes[0].name == "subA")
        #expect(directoryNodes[0].markdownFileCount == 2)
        #expect(fileNodes[0].name == "root.md")
    }

    @Test @MainActor func toggleFolderSelectsAndDeselectsAllChildren() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let subA = folderURL.appendingPathComponent("subA", isDirectory: true)
        try? FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)

        let rootFile = folderURL.appendingPathComponent("root.md")
        let subFile1 = subA.appendingPathComponent("a1.md")
        let subFile2 = subA.appendingPathComponent("a2.md")

        let model = FolderWatchFileSelectionModel(
            folderURL: folderURL,
            fileURLs: [rootFile, subFile1, subFile2]
        )

        let folderNode = model.rootNodes.first(where: { $0.isDirectory })!

        // All selected by default — toggling deselects all children
        #expect(model.isNodeFullySelected(folderNode))
        model.toggleFolder(folderNode)
        #expect(!model.isSelected(subFile1))
        #expect(!model.isSelected(subFile2))
        #expect(model.isSelected(rootFile))
        #expect(model.selectedCount == 1)

        // Toggle again selects all children
        model.toggleFolder(folderNode)
        #expect(model.isSelected(subFile1))
        #expect(model.isSelected(subFile2))
        #expect(model.selectedCount == 3)
    }

    @Test @MainActor func partialSelectionDetection() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let subA = folderURL.appendingPathComponent("subA", isDirectory: true)
        try? FileManager.default.createDirectory(at: subA, withIntermediateDirectories: true)

        let subFile1 = subA.appendingPathComponent("a1.md")
        let subFile2 = subA.appendingPathComponent("a2.md")

        let model = FolderWatchFileSelectionModel(
            folderURL: folderURL,
            fileURLs: [subFile1, subFile2]
        )

        let folderNode = model.rootNodes.first(where: { $0.isDirectory })!

        #expect(model.isNodeFullySelected(folderNode))
        #expect(!model.isNodePartiallySelected(folderNode))

        model.toggleFile(subFile1)
        #expect(!model.isNodeFullySelected(folderNode))
        #expect(model.isNodePartiallySelected(folderNode))
    }

    @Test @MainActor func emptyFolderProducesEmptyTree() {
        let folderURL = makeTemporaryDirectory()
        defer { cleanup(folderURL) }

        let model = FolderWatchFileSelectionModel(folderURL: folderURL, fileURLs: [])

        #expect(model.rootNodes.isEmpty)
        #expect(model.totalCount == 0)
        #expect(model.selectedCount == 0)
        #expect(!model.exceedsPerformanceThreshold)
    }
}
