import SwiftUI

/// Every accessibility identifier used by production views and `minimarkUITests`
/// goes through this enum. UI tests reach the raw values via `@testable import minimark`.
enum ReaderAccessibilityID: String {
    case readerPreviewSummary = "reader-preview-summary"
    case tocButton = "toc-button"
    case sidebarColumn = "sidebar-column"
    case sidebarGroupToggle = "sidebar-group-toggle"
    case sidebarPlacementToggle = "sidebar-placement-toggle"
    case folderWatchToolbarButton = "folder-watch-toolbar-button"
    case editFavoritesButton = "edit-favorites-button"
    case folderWatchSheet = "folder-watch-sheet"
    case folderWatchSummaryCard = "folder-watch-summary-card"
    case folderWatchCancelButton = "folder-watch-cancel-button"
    case folderWatchStartButton = "folder-watch-start-button"
    case folderWatchDialogStartButton = "folder-watch-dialog-start-button"
    case folderWatchChooseSubdirectoriesButton = "folder-watch-choose-subdirectories-button"
    case fileSelectionSkipButton = "file-selection-skip-button"
    case fileSelectionOpenButton = "file-selection-open-button"
    case autoOpenKeepCurrentButton = "auto-open-keep-current-button"
    case autoOpenSelectMoreButton = "auto-open-select-more-button"

    static func sidebarDocument(title: String) -> String {
        "sidebar-document-\(title)"
    }
}

extension View {
    func accessibilityIdentifier(_ id: ReaderAccessibilityID) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
