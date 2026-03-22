import Foundation

enum ReaderWindowUITestLaunchAction {
    case none
    case simulateAutoOpenWatchFlow
    case presentWatchFolderSheet(URL)
    case startWatchingFolder(URL)
}

struct ReaderWindowUITestFlowSupport {
    static func resolveLaunchAction(
        configuration: ReaderUITestLaunchConfiguration,
        hostWindowAvailable: Bool
    ) -> ReaderWindowUITestLaunchAction {
        guard configuration.isUITestModeEnabled else {
            return .none
        }

        guard hostWindowAvailable else {
            return .none
        }

        if configuration.shouldSimulateAutoOpenWatchFlow {
            return .simulateAutoOpenWatchFlow
        }

        guard let watchFolderURL = configuration.watchFolderURL else {
            return .none
        }

        if configuration.shouldPresentWatchFolderSheet {
            return .presentWatchFolderSheet(watchFolderURL)
        }

        if configuration.shouldAutoStartWatchingFolder {
            return .startWatchingFolder(watchFolderURL)
        }

        return .none
    }

    static func startAutoOpenWatchFlow(
        startWatchingFolder: (URL) -> Void,
        cancelExistingTask: () -> Void,
        waitForFolderWatchStartup: @escaping () async -> Void,
        assignTask: (Task<Void, Never>) -> Void
    ) {
        let watchFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-ui-watch-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: watchFolderURL, withIntermediateDirectories: true)
            startWatchingFolder(watchFolderURL)

            cancelExistingTask()
            let task = Task { @MainActor in
                let fileURL = watchFolderURL.appendingPathComponent("auto-open.md")
                await waitForFolderWatchStartup()
                try? "# Auto Open\n\nFirst version\n".write(to: fileURL, atomically: true, encoding: .utf8)
                try? await Task.sleep(for: .milliseconds(1800))
                try? "# Auto Open\n\nLater version\n".write(to: fileURL, atomically: true, encoding: .utf8)
            }
            assignTask(task)
        } catch let error {
            #if DEBUG
            assertionFailure("Failed to start auto-open watch flow: \(error)")
            #else
            NSLog("Failed to start auto-open watch flow: \(error)")
            #endif
        }
    }

    static func waitForFolderWatchStartup(
        isSessionActive: @escaping () -> Bool
    ) async {
        let minimumDelay: Duration = .milliseconds(1200)
        let pollInterval: Duration = .milliseconds(150)
        let startupDeadline = ContinuousClock.now + .seconds(4)

        try? await Task.sleep(for: minimumDelay)

        while !isSessionActive(),
              ContinuousClock.now < startupDeadline {
            try? await Task.sleep(for: pollInterval)
        }
    }
}
