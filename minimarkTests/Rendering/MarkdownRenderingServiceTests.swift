//
//  MarkdownRenderingServiceTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite
struct MarkdownRenderingServiceTests {
    private let service = MarkdownRenderingService()
    private let theme = ThemeKind.blackOnWhite.themeDefinition

    @Test func renderProducesHTMLDocument() throws {
        let result = try service.render(
            markdown: "# Hello World",
            changedRegions: [],
            unsavedChangedRegions: [],
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        )

        let containsHTML = result.htmlDocument.contains("<html") || result.htmlDocument.contains("<!DOCTYPE")
        #expect(containsHTML)
    }

    @Test func renderPreservesChangedRegions() throws {
        let region = ChangedRegion(blockIndex: 0, lineRange: 0...1, kind: .edited)
        let result = try service.render(
            markdown: "# Hello",
            changedRegions: [region],
            unsavedChangedRegions: [],
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        )

        #expect(result.changedRegions == [region])
    }

    @Test func renderSetsRenderedAtTimestamp() throws {
        let before = Date()
        let result = try service.render(
            markdown: "# Hello",
            changedRegions: [],
            unsavedChangedRegions: [],
            theme: theme,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            readerThemeOverride: nil
        )

        #expect(result.renderedAt >= before)
    }
}
