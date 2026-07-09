//
//  CalloutBlockRenderingTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite
struct CalloutBlockRenderingTests {
    private let service = MarkdownRenderingService()
    private let theme = ThemeKind.blackOnWhite.themeDefinition

    private func renderHTML(_ markdown: String) throws -> String {
        try service.render(
            markdown: markdown,
            changedRegions: [],
            unsavedChangedRegions: [],
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        ).htmlDocument
    }

    @Test func htmlDocumentIncludesCalloutsScript() throws {
        let html = try renderHTML("# Hello")
        #expect(html.contains("markdown-it-callouts.js"))
    }

    @Test func htmlDocumentIncludesCalloutCSS() throws {
        let html = try renderHTML("# Hello")
        #expect(html.contains("callout-blocks.css"))
    }

    @Test func runtimeAssetsIncludesCalloutsScriptPath() throws {
        let assets = try BundledAssets.requiredRuntimeAssets()
        #expect(assets.calloutsScriptPath != nil)
        #expect(assets.calloutsScriptPath == BundledAssets.calloutsScriptPath)
    }

    @Test func runtimeAssetsIncludesCalloutsCSSPath() throws {
        let assets = try BundledAssets.requiredRuntimeAssets()
        #expect(assets.calloutsCSSPath != nil)
        #expect(assets.calloutsCSSPath == BundledAssets.calloutsCSSPath)
    }
}
