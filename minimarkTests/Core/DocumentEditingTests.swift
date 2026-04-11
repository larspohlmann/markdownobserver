import Foundation
import Testing
@testable import minimark

struct DocumentEditingTests {
    @Test func emptyStateHasDefaults() {
        let state = DocumentEditing.empty
        #expect(state.documentViewMode == .preview)
        #expect(state.isSourceEditing == false)
        #expect(state.hasUnsavedDraftChanges == false)
        #expect(state.draftMarkdown == nil)
        #expect(state.sourceEditorSeedMarkdown == "")
        #expect(state.unsavedChangedRegions.isEmpty)
        #expect(state.pendingSavedDraftDiffBaselineMarkdown == nil)
    }

    @Test func canSaveSourceDraftRequiresEditingAndUnsavedChanges() {
        var state = DocumentEditing.empty
        #expect(state.canSaveSourceDraft == false)

        state.isSourceEditing = true
        #expect(state.canSaveSourceDraft == false)

        state.hasUnsavedDraftChanges = true
        #expect(state.canSaveSourceDraft == true)
    }

    @Test func canDiscardSourceDraftRequiresEditing() {
        var state = DocumentEditing.empty
        #expect(state.canDiscardSourceDraft == false)
        state.isSourceEditing = true
        #expect(state.canDiscardSourceDraft == true)
    }
}
