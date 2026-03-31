//
//  MarkdownImageResolverTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct MarkdownImageResolverTests {
    private let testDir: URL
    private let imageFile: URL
    private let imageBase64: String

    init() throws {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-image-resolver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        // Write a tiny 1x1 red PNG.
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==")!
        imageFile = testDir.appendingPathComponent("test.png")
        try pngData.write(to: imageFile)
        imageBase64 = pngData.base64EncodedString()

        let subdir = testDir.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try pngData.write(to: subdir.appendingPathComponent("photo.png"))
    }

    // MARK: - Relative paths

    @Test func resolvesRelativePath() throws {
        let md = "![alt](assets/photo.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown.contains("data:image/png;base64,"))
        #expect(!result.markdown.contains("assets/photo.png"))
    }

    @Test func resolvesRelativePathWithTitle() throws {
        let md = #"![alt](assets/photo.png "My Title")"#
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown.contains("data:image/png;base64,"))
        #expect(result.markdown.contains(#""My Title")"#))
    }

    // MARK: - file:// URLs

    @Test func resolvesFileURL() throws {
        let md = "![img](file:///\(imageFile.path))"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown.contains("data:image/png;base64,"))
    }

    // MARK: - Non-local URLs left as-is

    @Test func skipsHTTPURLs() throws {
        let md = "![alt](https://example.com/img.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    @Test func skipsDataURIs() throws {
        let md = "![alt](data:image/png;base64,abc)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    @Test func skipsUnknownSchemes() throws {
        let md = "![alt](mailto:test@example.com)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    // MARK: - Missing files

    @Test func skipsMissingFiles() throws {
        let md = "![alt](does-not-exist.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    // MARK: - Non-image files

    @Test func skipsNonImageFiles() throws {
        let txtFile = testDir.appendingPathComponent("readme.txt")
        try "hello".write(to: txtFile, atomically: true, encoding: .utf8)
        let md = "![alt](readme.txt)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    // MARK: - Code blocks not rewritten

    @Test func skipsImagesInsideFencedCodeBlock() throws {
        let md = """
        ```
        ![alt](assets/photo.png)
        ```
        """
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(!result.markdown.contains("data:image/png;base64,"))
        #expect(result.markdown.contains("assets/photo.png"))
    }

    @Test func skipsImagesInsideInlineCode() throws {
        let md = "Use `![alt](assets/photo.png)` in your markdown."
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(!result.markdown.contains("data:image/png;base64,"))
    }

    // MARK: - No document directory

    @Test func returnsUnchangedWhenNoDocumentDir() throws {
        let md = "![alt](test.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: nil)
        #expect(result.markdown == md)
    }

    // MARK: - Fragments

    @Test func skipsFragmentReferences() throws {
        let md = "![alt](#section)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.markdown == md)
    }

    // MARK: - needsDirectoryAccess

    @Test func needsDirectoryAccessIsFalseWhenImagesResolve() throws {
        let md = "![alt](assets/photo.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.needsDirectoryAccess == false)
    }

    @Test func needsDirectoryAccessIsFalseWhenNoImages() throws {
        let md = "Hello world"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.needsDirectoryAccess == false)
    }

    @Test func needsDirectoryAccessIsFalseWhenNoDocDir() throws {
        let md = "![alt](test.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: nil)
        #expect(result.needsDirectoryAccess == false)
    }

    @Test func needsDirectoryAccessIsFalseForMissingFiles() throws {
        let md = "![alt](does-not-exist.png)"
        let result = MarkdownImageResolver.resolve(markdown: md, documentDirectoryURL: testDir)
        #expect(result.needsDirectoryAccess == false)
    }
}
