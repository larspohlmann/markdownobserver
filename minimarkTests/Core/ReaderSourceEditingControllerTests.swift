import Testing
@testable import minimark

@MainActor
@Suite("SourceEditingController")
struct ReaderSourceEditingControllerTests {
    @Test("startEditing begins session with saved markdown")
    func startEditingBeginsSession() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: true,
            isCurrentFileMissing: false
        )
        #expect(sut.isSourceEditing)
        #expect(sut.draftMarkdown == "# Hello")
        #expect(sut.sourceEditorSeedMarkdown == "# Hello")
        #expect(!sut.hasUnsavedDraftChanges)
    }

    @Test("startEditing does nothing without open document")
    func startEditingRequiresOpenDocument() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: false,
            isCurrentFileMissing: false
        )
        #expect(!sut.isSourceEditing)
    }

    @Test("startEditing does nothing when file is missing")
    func startEditingRequiresFileNotMissing() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: true,
            isCurrentFileMissing: true
        )
        #expect(!sut.isSourceEditing)
    }

    @Test("updateDraft sets draft and flags unsaved changes")
    func updateDraftSetsDraft() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: true,
            isCurrentFileMissing: false
        )
        sut.updateDraft(
            "# Changed",
            savedMarkdown: "# Hello",
            unsavedChangedRegions: [ChangedRegion(blockIndex: 0, lineRange: 0...0)]
        )
        #expect(sut.draftMarkdown == "# Changed")
        #expect(sut.hasUnsavedDraftChanges)
        #expect(sut.unsavedChangedRegions.count == 1)
    }

    @Test("finishSession clears editing state")
    func finishSessionClearsState() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: true,
            isCurrentFileMissing: false
        )
        sut.finishSession(markdown: "# Saved")
        #expect(!sut.isSourceEditing)
        #expect(sut.draftMarkdown == nil)
        #expect(sut.sourceEditorSeedMarkdown == "# Saved")
        #expect(!sut.hasUnsavedDraftChanges)
    }

    @Test("reset clears all editing state")
    func resetClearsState() {
        let sut = SourceEditingController()
        sut.startEditing(
            savedMarkdown: "# Hello",
            hasOpenDocument: true,
            isCurrentFileMissing: false
        )
        sut.reset()
        #expect(!sut.isSourceEditing)
        #expect(sut.draftMarkdown == nil)
        #expect(sut.unsavedChangedRegions.isEmpty)
    }

    @Test("setViewMode changes mode when document is open")
    func setViewModeChangesMode() {
        let sut = SourceEditingController()
        sut.setViewMode(.split, hasOpenDocument: true)
        #expect(sut.documentViewMode == .split)
    }

    @Test("setViewMode falls back to preview without open document")
    func setViewModeFallsBackWithoutDocument() {
        let sut = SourceEditingController()
        sut.setViewMode(.split, hasOpenDocument: false)
        #expect(sut.documentViewMode == .preview)
    }

    @Test("toggleViewMode cycles through modes")
    func toggleViewModeCycles() {
        let sut = SourceEditingController()
        #expect(sut.documentViewMode == .preview)
        sut.toggleViewMode()
        #expect(sut.documentViewMode == .split)
        sut.toggleViewMode()
        #expect(sut.documentViewMode == .source)
        sut.toggleViewMode()
        #expect(sut.documentViewMode == .preview)
    }

    @Test("canSaveSourceDraft requires editing and unsaved changes")
    func canSaveSourceDraft() {
        let sut = SourceEditingController()
        #expect(!sut.canSaveSourceDraft)

        sut.startEditing(savedMarkdown: "# Hello", hasOpenDocument: true, isCurrentFileMissing: false)
        #expect(!sut.canSaveSourceDraft)

        sut.updateDraft("# Changed", savedMarkdown: "# Hello", unsavedChangedRegions: [ChangedRegion(blockIndex: 0, lineRange: 0...0)])
        #expect(sut.canSaveSourceDraft)
    }

    @Test("canDiscardSourceDraft requires editing")
    func canDiscardSourceDraft() {
        let sut = SourceEditingController()
        #expect(!sut.canDiscardSourceDraft)

        sut.startEditing(savedMarkdown: "# Hello", hasOpenDocument: true, isCurrentFileMissing: false)
        #expect(sut.canDiscardSourceDraft)
    }
}
