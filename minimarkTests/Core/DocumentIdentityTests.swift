import Foundation
import Testing
@testable import minimark

struct DocumentIdentityTests {
    @Test func emptyStateHasDefaults() {
        let state = DocumentIdentity.empty
        #expect(state.fileURL == nil)
        #expect(state.fileDisplayName == "")
        #expect(state.documentLoadState == .ready)
        #expect(state.isCurrentFileMissing == false)
        #expect(state.lastError == nil)
        #expect(state.openInApplications.isEmpty)
        #expect(state.needsImageDirectoryAccess == false)
        #expect(state.currentOpenOrigin == .manual)
    }

    @Test func hasOpenDocumentWhenFileURLSet() {
        var state = DocumentIdentity.empty
        #expect(state.hasOpenDocument == false)
        state.fileURL = URL(fileURLWithPath: "/test.md")
        #expect(state.hasOpenDocument == true)
    }

    @Test func isDeferredDocumentMatchesDeferredLoadState() {
        var state = DocumentIdentity.empty
        state.documentLoadState = .deferred
        #expect(state.isDeferredDocument == true)
        state.documentLoadState = .ready
        #expect(state.isDeferredDocument == false)
    }

    @Test func windowTitleFallsBackWhenNoFile() {
        let state = DocumentIdentity.empty
        #expect(state.windowTitle == "MarkdownObserver")
    }

    @Test func windowTitleIncludesFileName() {
        var state = DocumentIdentity.empty
        state.fileDisplayName = "README.md"
        #expect(state.windowTitle == "README.md - MarkdownObserver")
    }
}
