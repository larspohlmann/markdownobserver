import Foundation

struct ReaderUITestLaunchConfiguration {
    static let enableArgument = "-minimark-ui-test"
    static let presentWatchFolderSheetArgument = "-minimark-present-watch-folder-sheet"
    static let autoStartWatchFolderArgument = "-minimark-auto-start-watch-folder"
    static let simulateAutoOpenWatchFlowArgument = "-minimark-simulate-auto-open-watch-flow"
    static let simulateGroupedSidebarArgument = "-minimark-simulate-grouped-sidebar"
    static let simulateScreenshotShowcaseArgument = "-minimark-simulate-screenshot-showcase"
    static let watchFolderPathEnvironmentKey = "MINIMARK_UI_TEST_WATCH_FOLDER_PATH"
    static let screenshotContentPathEnvironmentKey = "MINIMARK_SCREENSHOT_CONTENT_PATH"
    static let screenshotActiveFileEnvironmentKey = "MINIMARK_SCREENSHOT_ACTIVE_FILE"
    static let screenshotExpandFirstEditEnvironmentKey = "MINIMARK_SCREENSHOT_EXPAND_FIRST_EDIT"
    static let screenshotWatchScopeEnvironmentKey = "MINIMARK_SCREENSHOT_WATCH_SCOPE"
    static let screenshotOpenExclusionEnvironmentKey = "MINIMARK_SCREENSHOT_OPEN_EXCLUSION"
    static let screenshotSplitViewEnvironmentKey = "MINIMARK_SCREENSHOT_SPLIT_VIEW"
    static let screenshotShowWatchSheetEnvironmentKey = "MINIMARK_SCREENSHOT_SHOW_WATCH_SHEET"
    static let screenshotExcludedPathsEnvironmentKey = "MINIMARK_SCREENSHOT_EXCLUDED_PATHS"
    static let screenshotExpandedPathsEnvironmentKey = "MINIMARK_SCREENSHOT_EXPANDED_PATHS"
    static let screenshotShowWatchMenuEnvironmentKey = "MINIMARK_SCREENSHOT_SHOW_WATCH_MENU"
    static let screenshotWindowSizeEnvironmentKey = "MINIMARK_SCREENSHOT_WINDOW_SIZE"

    let isUITestModeEnabled: Bool
    let shouldPresentWatchFolderSheet: Bool
    let shouldAutoStartWatchingFolder: Bool
    let shouldSimulateAutoOpenWatchFlow: Bool
    let shouldSimulateGroupedSidebar: Bool
    let shouldSimulateScreenshotShowcase: Bool
    let watchFolderURL: URL?
    let screenshotContentURL: URL?

    static var current: ReaderUITestLaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let isUITestModeEnabled = arguments.contains(enableArgument)
        let shouldPresentWatchFolderSheet = isUITestModeEnabled && arguments.contains(presentWatchFolderSheetArgument)
        let shouldAutoStartWatchingFolder = isUITestModeEnabled && arguments.contains(autoStartWatchFolderArgument)
        let shouldSimulateAutoOpenWatchFlow = isUITestModeEnabled && arguments.contains(simulateAutoOpenWatchFlowArgument)
        let shouldSimulateGroupedSidebar = isUITestModeEnabled && arguments.contains(simulateGroupedSidebarArgument)
        let shouldSimulateScreenshotShowcase = isUITestModeEnabled && arguments.contains(simulateScreenshotShowcaseArgument)

        let watchFolderURL: URL?
        if let folderPath = processInfo.environment[watchFolderPathEnvironmentKey], !folderPath.isEmpty {
            watchFolderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        } else {
            watchFolderURL = nil
        }

        let screenshotContentURL: URL?
        if let contentPath = processInfo.environment[screenshotContentPathEnvironmentKey], !contentPath.isEmpty {
            screenshotContentURL = URL(fileURLWithPath: contentPath, isDirectory: true)
        } else {
            screenshotContentURL = nil
        }

        return ReaderUITestLaunchConfiguration(
            isUITestModeEnabled: isUITestModeEnabled,
            shouldPresentWatchFolderSheet: shouldPresentWatchFolderSheet,
            shouldAutoStartWatchingFolder: shouldAutoStartWatchingFolder,
            shouldSimulateAutoOpenWatchFlow: shouldSimulateAutoOpenWatchFlow,
            shouldSimulateGroupedSidebar: shouldSimulateGroupedSidebar,
            shouldSimulateScreenshotShowcase: shouldSimulateScreenshotShowcase,
            watchFolderURL: watchFolderURL,
            screenshotContentURL: screenshotContentURL
        )
    }
}