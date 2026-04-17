import Foundation

/// Every accessibility identifier used by production views and `minimarkUITests`
/// goes through this enum. UI tests access the raw values because `minimarkShared`
/// is compiled into the UI-test target as well as the app target.
enum AccessibilityID: String {
    case previewSummary = "preview-summary"
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
