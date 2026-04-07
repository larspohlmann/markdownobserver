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
        #expect(state.unacknowledgedExternalChangeKind == .modified)
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

    @Test func isDeferredDocumentMatchesDeferredLoadState() {
        var state = ReaderDocumentState.empty
        state.documentLoadState = .deferred
        #expect(state.isDeferredDocument == true)
        state.documentLoadState = .ready
        #expect(state.isDeferredDocument == false)
    }

    @Test func canStartSourceEditingRequiresOpenFileAndNotMissingAndNotEditing() {
        var state = ReaderDocumentState.empty
        // No file — cannot start editing
        #expect(state.canStartSourceEditing == false)

        // Has file — can start editing
        state.fileURL = URL(fileURLWithPath: "/test.md")
        #expect(state.canStartSourceEditing == true)

        // File missing — cannot start editing
        state.isCurrentFileMissing = true
        #expect(state.canStartSourceEditing == false)

        // File present but already editing — cannot start again
        state.isCurrentFileMissing = false
        state.isSourceEditing = true
        #expect(state.canStartSourceEditing == false)
    }

    @Test func canSaveSourceDraftRequiresEditingAndUnsavedChanges() {
        var state = ReaderDocumentState.empty
        // Empty state — cannot save
        #expect(state.canSaveSourceDraft == false)

        // Editing but no unsaved changes — cannot save
        state.isSourceEditing = true
        #expect(state.canSaveSourceDraft == false)

        // Editing with unsaved changes — can save
        state.hasUnsavedDraftChanges = true
        #expect(state.canSaveSourceDraft == true)
    }

    @Test func canDiscardSourceDraftRequiresEditing() {
        var state = ReaderDocumentState.empty
        #expect(state.canDiscardSourceDraft == false)
        state.isSourceEditing = true
        #expect(state.canDiscardSourceDraft == true)
    }

    @Test func statusBarTimestampFallsBackToModificationDate() {
        var state = ReaderDocumentState.empty
        let date = Date()
        state.fileLastModifiedAt = date
        #expect(state.statusBarTimestamp == .lastModified(date))
    }

    @Test func statusBarTimestampFallsBackToLastRefreshAt() {
        var state = ReaderDocumentState.empty
        let date = Date()
        state.lastRefreshAt = date
        #expect(state.statusBarTimestamp == .updated(date))
    }

    @Test func statusBarTimestampIsNilWhenNoDatesSet() {
        let state = ReaderDocumentState.empty
        #expect(state.statusBarTimestamp == nil)
    }

    @Test func resetToEmptyClearsAllState() {
        var state = ReaderDocumentState.empty
        state.fileURL = URL(fileURLWithPath: "/test.md")
        state.fileDisplayName = "test.md"
        state.savedMarkdown = "# Hello"
        state.isSourceEditing = true
        state.hasUnsavedDraftChanges = true
        state.hasUnacknowledgedExternalChange = true
        state.lastExternalChangeAt = Date()
        state.isCurrentFileMissing = true

        state = .empty

        #expect(state.fileURL == nil)
        #expect(state.fileDisplayName == "")
        #expect(state.savedMarkdown == "")
        #expect(state.isSourceEditing == false)
        #expect(state.hasUnsavedDraftChanges == false)
        #expect(state.hasUnacknowledgedExternalChange == false)
        #expect(state.unacknowledgedExternalChangeKind == .modified)
        #expect(state.lastExternalChangeAt == nil)
        #expect(state.isCurrentFileMissing == false)
    }

    @Test func decoratedWindowTitleNoAsteriskWhenNoChanges() {
        var state = ReaderDocumentState.empty
        state.fileDisplayName = "README.md"
        #expect(state.decoratedWindowTitle.hasPrefix("*") == false)
        #expect(state.decoratedWindowTitle == "README.md - MarkdownObserver")
    }

    @Test func externalChangeThenAcknowledgeCycle() {
        var state = ReaderDocumentState.empty
        state.fileDisplayName = "README.md"

        state.hasUnacknowledgedExternalChange = true
        #expect(state.decoratedWindowTitle.hasPrefix("*"))

        state.hasUnacknowledgedExternalChange = false
        #expect(state.decoratedWindowTitle.hasPrefix("*") == false)
    }
}
