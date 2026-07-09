//
//  MarkdownLinkResolverTests.swift
//  minimarkTests
//

import Testing
import Foundation
@testable import minimark

@Suite
struct MarkdownLinkResolverTests {
    private let bundlePath = "/Applications/MarkdownObserver.app"
    private let documentDir = "/Users/me/notes"

    @Test
    func resolvesRelativeFileAgainstDocumentDirectory() {
        // After WKWebView resolves "file.md" against the bundle baseURL, the
        // navigation delegate sees a bundle-prefixed file:// URL.
        let bundleResolved = URL(fileURLWithPath: "\(bundlePath)/file.md")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: bundleResolved,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/file.md")
    }

    @Test
    func resolvesRelativeSubdirectoryPath() {
        let bundleResolved = URL(fileURLWithPath: "\(bundlePath)/sub/other.md")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: bundleResolved,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/sub/other.md")
    }

    @Test
    func passesAbsolutePathThrough() {
        let absolute = URL(fileURLWithPath: "/var/tmp/elsewhere.md")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: absolute,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "/var/tmp/elsewhere.md")
    }

    @Test
    func stripsFragment() {
        var components = URLComponents()
        components.scheme = "file"
        components.path = "\(bundlePath)/file.md"
        components.fragment = "section"
        let withFragment = components.url!

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: withFragment,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/file.md")
        #expect(resolved?.fragment == nil)
    }

    @Test
    func returnsNilForNonMarkdownExtension() {
        let png = URL(fileURLWithPath: "\(bundlePath)/image.png")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: png,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved == nil)
    }

    @Test
    func returnsNilForNoExtension() {
        let noExt = URL(fileURLWithPath: "\(bundlePath)/README")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: noExt,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved == nil)
    }

    @Test
    func acceptsMarkdownExtension() {
        let longExt = URL(fileURLWithPath: "\(bundlePath)/file.markdown")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: longExt,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/file.markdown")
    }

    @Test
    func acceptsMdownExtension() {
        let mdown = URL(fileURLWithPath: "\(bundlePath)/file.mdown")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: mdown,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/file.mdown")
    }

    @Test
    func extensionMatchIsCaseInsensitive() {
        let upper = URL(fileURLWithPath: "\(bundlePath)/file.MD")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: upper,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/file.MD")
    }

    @Test
    func returnsNilWhenDocumentDirectoryUnknown() {
        let bundleResolved = URL(fileURLWithPath: "\(bundlePath)/file.md")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: bundleResolved,
            documentDirectoryPath: nil,
            bundlePath: bundlePath
        )

        #expect(resolved == nil)
    }

    @Test
    func returnsNilForNonFileURL() {
        let https = URL(string: "https://example.com/notes.md")!

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: https,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved == nil)
    }

    @Test
    func resolvesFileWithSpacesInName() {
        // WKWebView decodes percent-encoded hrefs before the navigation
        // delegate sees them, so a markdown link `[x](my%20file.md)` arrives
        // with a space in `.path`. Confirm the resolver passes it through.
        let bundleResolved = URL(fileURLWithPath: "\(bundlePath)/my file.md")

        let resolved = MarkdownLinkResolver.resolveMarkdownLink(
            url: bundleResolved,
            documentDirectoryPath: documentDir,
            bundlePath: bundlePath
        )

        #expect(resolved?.path == "\(documentDir)/my file.md")
    }
}
