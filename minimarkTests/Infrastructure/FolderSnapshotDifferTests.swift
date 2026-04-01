//
//  FolderSnapshotDifferTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderSnapshotDifferTests {
    @Test func buildMetadataSnapshotReturnsSnapshotsWithNilMarkdown() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("note.md")
        try "# Hello".write(to: fileURL, atomically: false, encoding: .utf8)

        let differ = FolderSnapshotDiffer()
        let snapshot = try differ.buildMetadataSnapshot(
            folderURL: directoryURL,
            includeSubfolders: false,
            excludedSubdirectoryURLs: []
        )

        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        #expect(snapshot.count == 1)
        #expect(snapshot[normalizedFileURL] != nil)
        #expect(snapshot[normalizedFileURL]?.markdown == nil)
        #expect(snapshot[normalizedFileURL]?.fileSize ?? 0 > 0)
    }

    @Test func withContentPopulatesMarkdownFromFileURL() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("note.md")
        try "# Hello".write(to: fileURL, atomically: false, encoding: .utf8)

        let metadata = FolderFileMetadata(url: fileURL)
        let metadataOnly = FolderFileSnapshot(metadata: metadata)
        #expect(metadataOnly.markdown == nil)

        let populated = metadataOnly.withContent(from: fileURL)
        #expect(populated.markdown == "# Hello")
        #expect(populated.fileSize == metadataOnly.fileSize)
        #expect(populated.modificationDate == metadataOnly.modificationDate)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
