//
//  SourceHTMLDocumentCacheTests.swift
//  minimarkTests
//

import Testing
@testable import minimark

@Suite
struct SourceHTMLDocumentCacheTests {

    private static func makeSettings(
        readerTheme: ThemeKind = .blackOnWhite,
        baseFontSize: Double = 15
    ) -> ReaderSettings {
        ReaderSettings(
            appAppearance: .system,
            readerTheme: readerTheme,
            syntaxTheme: .monokai,
            baseFontSize: baseFontSize,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: false,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            recentWatchedFolders: [],
            recentManuallyOpenedFiles: []
        )
    }

    @Test func returnsEmptyDocumentBeforeFirstRefresh() {
        let cache = SourceHTMLDocumentCache()
        #expect(cache.document == "")
    }

    @Test func refreshProducesNonEmptyDocument() {
        var cache = SourceHTMLDocumentCache()
        let settings = Self.makeSettings()
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: false)
        #expect(!cache.document.isEmpty)
        #expect(cache.document.contains("<!DOCTYPE html>"))
    }

    @Test func skipsRefreshWhenInputsUnchanged() {
        var cache = SourceHTMLDocumentCache()
        let settings = Self.makeSettings()
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: false)
        let first = cache.document
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: false)
        #expect(cache.document == first)
    }

    @Test func refreshesWhenMarkdownChanges() {
        var cache = SourceHTMLDocumentCache()
        let settings = Self.makeSettings()
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: false)
        let first = cache.document
        cache.refreshIfNeeded(markdown: "# World", settings: settings, isEditable: false)
        #expect(cache.document != first)
    }

    @Test func refreshesWhenEditableChanges() {
        var cache = SourceHTMLDocumentCache()
        let settings = Self.makeSettings()
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: false)
        let first = cache.document
        cache.refreshIfNeeded(markdown: "# Hello", settings: settings, isEditable: true)
        #expect(cache.document != first)
    }

    @Test func refreshesWhenSettingsChange() {
        var cache = SourceHTMLDocumentCache()
        cache.refreshIfNeeded(
            markdown: "# Hello",
            settings: Self.makeSettings(baseFontSize: 15),
            isEditable: false
        )
        let first = cache.document
        cache.refreshIfNeeded(
            markdown: "# Hello",
            settings: Self.makeSettings(baseFontSize: 20),
            isEditable: false
        )
        #expect(cache.document != first)
    }
}
