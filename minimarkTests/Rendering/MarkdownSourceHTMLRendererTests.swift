//
//  MarkdownSourceHTMLRendererTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite
struct MarkdownSourceHTMLRendererTests {
    private var defaultSettings: ReaderSettings { .default }

    @Test func makeHTMLDocumentContainsDoctype() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("<!DOCTYPE html>"))
    }

    @Test func makeHTMLDocumentContainsSourceRoot() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("minimark-source-root"))
    }

    @Test func editableDocumentContainsBootstrapScript() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("__minimarkSourceBootstrapStatus"))
    }

    @Test func readOnlyDocumentContainsBootstrapStatus() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: false
        )

        #expect(html.contains("__minimarkSourceBootstrapStatus"))
    }

    @Test func htmlDocumentContainsCSSVariables() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("--reader-bg"))
        #expect(html.contains("--reader-fg"))
    }

    @Test func emptyMarkdownProducesValidHTML() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("<html"))
        #expect(html.contains("</html>"))
    }

    @Test func sourceRootIncludesOverlayAwareTopPadding() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        let expectedPadding = Int(OverlayInsetCalculator.defaultScrollTargetTopInset.rounded())
        #expect(html.contains("padding-top: \(expectedPadding)px"))
    }

    @Test func makeHTMLDocumentContainsContentSecurityPolicy() {
        let html = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: defaultSettings,
            isEditable: true
        )

        #expect(html.contains("Content-Security-Policy"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("script-src 'unsafe-inline' file:"))
        #expect(html.contains("img-src data: https:"))
    }

    @Test func differentThemesProduceDifferentCSS() {
        var lightSettings = defaultSettings
        lightSettings.readerTheme = .blackOnWhite

        var darkSettings = defaultSettings
        darkSettings.readerTheme = .whiteOnBlack

        let lightHTML = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: lightSettings,
            isEditable: false
        )
        let darkHTML = MarkdownSourceHTMLRenderer.makeHTMLDocument(
            markdown: "# Hello",
            settings: darkSettings,
            isEditable: false
        )

        #expect(lightHTML != darkHTML)
    }
}
