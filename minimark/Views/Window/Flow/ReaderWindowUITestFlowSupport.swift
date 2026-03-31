import Foundation

enum ReaderWindowUITestLaunchAction {
    case none
    case simulateAutoOpenWatchFlow
    case simulateGroupedSidebar
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

        if configuration.shouldSimulateGroupedSidebar {
            return .simulateGroupedSidebar
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

    static func startGroupedSidebarFlow(
        openDocumentsBurst: ([URL]) -> Void
    ) {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-ui-grouped-\(UUID().uuidString)", isDirectory: true)

        let subdirectories = [
            "project",
            "project/docs",
            "project/plans"
        ]

        let files: [(subdirectory: String, name: String, content: String, daysAgo: Int)] = [
            ("project", "README.md", "# README\n\nProject overview.", 2),
            ("project", "CONTRIBUTING.md", "# Contributing\n\nHow to contribute.", 5),
            ("project", "CHANGELOG.md", "# Changelog\n\n## v1.0\n- Initial release", 3),
            ("project", "SECURITY.md", "# Security\n\nReport vulnerabilities.", 7),
            ("project/docs", "BUILDING.md", "# Building\n\nBuild instructions.", 7),
            ("project/docs", "ARCHITECTURE.md", "# Architecture\n\nSystem overview.", 14),
            ("project/plans", "sidebar-redesign.md", "# Sidebar Redesign\n\nNew grouped layout.", 0),
            ("project/plans", "roadmap.md", "# Roadmap\n\n## Q2 2026\n- Feature A", 1),
        ]

        do {
            for subdirectory in subdirectories {
                let directoryURL = baseURL.appendingPathComponent(subdirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            var fileURLs: [URL] = []
            for file in files {
                let fileURL = baseURL
                    .appendingPathComponent(file.subdirectory)
                    .appendingPathComponent(file.name)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)

                let modificationDate = Calendar.current.date(
                    byAdding: .day, value: -file.daysAgo, to: Date()
                ) ?? Date()
                try FileManager.default.setAttributes(
                    [.modificationDate: modificationDate],
                    ofItemAtPath: fileURL.path(percentEncoded: false)
                )
                fileURLs.append(fileURL)
            }

            openDocumentsBurst(fileURLs)
        } catch {
            #if DEBUG
            assertionFailure("Failed to start grouped sidebar flow: \(error)")
            #else
            NSLog("Failed to start grouped sidebar flow: \(error)")
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
