import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderAccessibilityIDTests {

    // Raw values are part of the UI-test contract. A change here is a breaking
    // change to external UI tests and must be made deliberately.
    @Test func rawValuesAreStable() {
        let expected: [(ReaderAccessibilityID, String)] = [
            (.readerPreviewSummary, "reader-preview-summary"),
            (.tocButton, "toc-button"),
            (.sidebarColumn, "sidebar-column"),
            (.sidebarGroupToggle, "sidebar-group-toggle"),
            (.sidebarPlacementToggle, "sidebar-placement-toggle"),
            (.folderWatchToolbarButton, "folder-watch-toolbar-button"),
            (.editFavoritesButton, "edit-favorites-button"),
            (.folderWatchSheet, "folder-watch-sheet"),
            (.folderWatchSummaryCard, "folder-watch-summary-card"),
            (.folderWatchCancelButton, "folder-watch-cancel-button"),
            (.folderWatchStartButton, "folder-watch-start-button"),
            (.folderWatchDialogStartButton, "folder-watch-dialog-start-button"),
            (.folderWatchChooseSubdirectoriesButton, "folder-watch-choose-subdirectories-button"),
            (.fileSelectionSkipButton, "file-selection-skip-button"),
            (.fileSelectionOpenButton, "file-selection-open-button"),
            (.autoOpenKeepCurrentButton, "auto-open-keep-current-button"),
            (.autoOpenSelectMoreButton, "auto-open-select-more-button"),
        ]

        for (id, raw) in expected {
            #expect(id.rawValue == raw)
        }
    }

    @Test func sidebarDocumentIdentifierMatchesLegacyFormat() {
        #expect(ReaderAccessibilityID.sidebarDocument(title: "notes.md") == "sidebar-document-notes.md")
    }
}
