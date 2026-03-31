import Foundation

struct ReaderUITestLaunchConfiguration {
    static let enableArgument = "-minimark-ui-test"
    static let presentWatchFolderSheetArgument = "-minimark-present-watch-folder-sheet"
    static let autoStartWatchFolderArgument = "-minimark-auto-start-watch-folder"
    static let simulateAutoOpenWatchFlowArgument = "-minimark-simulate-auto-open-watch-flow"
    static let simulateGroupedSidebarArgument = "-minimark-simulate-grouped-sidebar"
    static let watchFolderPathEnvironmentKey = "MINIMARK_UI_TEST_WATCH_FOLDER_PATH"
    static let screenshotExpandFirstEditEnvironmentKey = "MINIMARK_SCREENSHOT_EXPAND_FIRST_EDIT"
    static let screenshotWatchScopeEnvironmentKey = "MINIMARK_SCREENSHOT_WATCH_SCOPE"
    static let screenshotOpenExclusionEnvironmentKey = "MINIMARK_SCREENSHOT_OPEN_EXCLUSION"
    static let screenshotExcludedPathsEnvironmentKey = "MINIMARK_SCREENSHOT_EXCLUDED_PATHS"
    static let screenshotExpandedPathsEnvironmentKey = "MINIMARK_SCREENSHOT_EXPANDED_PATHS"
    static let screenshotWindowSizeEnvironmentKey = "MINIMARK_SCREENSHOT_WINDOW_SIZE"

    let isUITestModeEnabled: Bool
    let shouldPresentWatchFolderSheet: Bool
    let shouldAutoStartWatchingFolder: Bool
    let shouldSimulateAutoOpenWatchFlow: Bool
    let shouldSimulateGroupedSidebar: Bool
    let watchFolderURL: URL?

    static var current: ReaderUITestLaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let isUITestModeEnabled = arguments.contains(enableArgument)
        let shouldPresentWatchFolderSheet = isUITestModeEnabled && arguments.contains(presentWatchFolderSheetArgument)
        let shouldAutoStartWatchingFolder = isUITestModeEnabled && arguments.contains(autoStartWatchFolderArgument)
        let shouldSimulateAutoOpenWatchFlow = isUITestModeEnabled && arguments.contains(simulateAutoOpenWatchFlowArgument)
        let shouldSimulateGroupedSidebar = isUITestModeEnabled && arguments.contains(simulateGroupedSidebarArgument)

        let watchFolderURL: URL?
        if let folderPath = processInfo.environment[watchFolderPathEnvironmentKey], !folderPath.isEmpty {
            watchFolderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        } else {
            watchFolderURL = nil
        }

        return ReaderUITestLaunchConfiguration(
            isUITestModeEnabled: isUITestModeEnabled,
            shouldPresentWatchFolderSheet: shouldPresentWatchFolderSheet,
            shouldAutoStartWatchingFolder: shouldAutoStartWatchingFolder,
            shouldSimulateAutoOpenWatchFlow: shouldSimulateAutoOpenWatchFlow,
            shouldSimulateGroupedSidebar: shouldSimulateGroupedSidebar,
            watchFolderURL: watchFolderURL
        )
    }
}