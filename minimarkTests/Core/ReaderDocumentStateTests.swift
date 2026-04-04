import Foundation
import Testing
@testable import minimark

struct ReaderDocumentStateTests {
    @Test func emptyStateHasDefaults() {
        let state = ReaderDocumentState.empty
        #expect(state.fileURL == nil)
        #expect(state.fileDisplayName == "")
        #expect(state.savedMarkdown == "")
        #expect(state.draftMarkdown == nil)
        #expect(state.sourceMarkdown == "")
        #expect(state.sourceEditorSeedMarkdown == "")
        #expect(state.renderedHTMLDocument == "")
        #expect(state.documentViewMode == .preview)
        #expect(state.documentLoadState == .ready)
        #expect(state.changedRegions.isEmpty)
        #expect(state.unsavedChangedRegions.isEmpty)
        #expect(state.lastRefreshAt == nil)
        #expect(state.lastExternalChangeAt == nil)
        #expect(state.fileLastModifiedAt == nil)
        #expect(state.hasUnacknowledgedExternalChange == false)
        #expect(state.openInApplications.isEmpty)
        #expect(state.lastError == nil)
        #expect(state.isCurrentFileMissing == false)
        #expect(state.isSourceEditing == false)
        #expect(state.hasUnsavedDraftChanges == false)
        #expect(state.needsImageDirectoryAccess == false)
        #expect(state.currentOpenOrigin == .manual)
    }

    @Test func windowTitleFallsBackWhenNoFile() {
        let state = ReaderDocumentState.empty
        #expect(state.windowTitle == "MarkdownObserver")
    }

    @Test func windowTitleIncludesFileName() {
        var state = ReaderDocumentState.empty
        state.fileDisplayName = "README.md"
        #expect(state.windowTitle == "README.md - MarkdownObserver")
    }

    @Test func decoratedWindowTitleShowsAsteriskForExternalChange() {
        var state = ReaderDocumentState.empty
        state.fileDisplayName = "README.md"
        state.hasUnacknowledgedExternalChange = true
        #expect(state.decoratedWindowTitle.hasPrefix("*"))
    }

    @Test func decoratedWindowTitleShowsAsteriskForUnsavedDraft() {
        var state = ReaderDocumentState.empty
        state.fileDisplayName = "README.md"
        state.hasUnsavedDraftChanges = true
        #expect(state.decoratedWindowTitle.hasPrefix("*"))
    }

    @Test func statusBarTimestampPrefersExternalChange() {
        var state = ReaderDocumentState.empty
        let date = Date()
        state.lastExternalChangeAt = date
        state.fileLastModifiedAt = date.addingTimeInterval(-10)
        #expect(state.statusBarTimestamp == .updated(date))
    }

    @Test func hasOpenDocumentWhenFileURLSet() {
        var state = ReaderDocumentState.empty
        #expect(state.hasOpenDocument == false)
        state.fileURL = URL(fileURLWithPath: "/test.md")
        #expect(state.hasOpenDocument == true)
    }
}
