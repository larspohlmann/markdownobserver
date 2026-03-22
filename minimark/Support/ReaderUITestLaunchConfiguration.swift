import Foundation

struct ReaderUITestLaunchConfiguration {
    static let enableArgument = "-minimark-ui-test"
    static let presentWatchFolderSheetArgument = "-minimark-present-watch-folder-sheet"
    static let autoStartWatchFolderArgument = "-minimark-auto-start-watch-folder"
    static let simulateAutoOpenWatchFlowArgument = "-minimark-simulate-auto-open-watch-flow"
    static let watchFolderPathEnvironmentKey = "MINIMARK_UI_TEST_WATCH_FOLDER_PATH"

    let isUITestModeEnabled: Bool
    let shouldPresentWatchFolderSheet: Bool
    let shouldAutoStartWatchingFolder: Bool
    let shouldSimulateAutoOpenWatchFlow: Bool
    let watchFolderURL: URL?

    static var current: ReaderUITestLaunchConfiguration {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let isUITestModeEnabled = arguments.contains(enableArgument)
        let shouldPresentWatchFolderSheet = isUITestModeEnabled && arguments.contains(presentWatchFolderSheetArgument)
        let shouldAutoStartWatchingFolder = isUITestModeEnabled && arguments.contains(autoStartWatchFolderArgument)
        let shouldSimulateAutoOpenWatchFlow = isUITestModeEnabled && arguments.contains(simulateAutoOpenWatchFlowArgument)

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
            watchFolderURL: watchFolderURL
        )
    }
}