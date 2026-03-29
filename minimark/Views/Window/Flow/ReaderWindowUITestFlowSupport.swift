import Foundation

enum ReaderWindowUITestLaunchAction {
    case none
    case simulateAutoOpenWatchFlow
    case simulateGroupedSidebar
    case simulateScreenshotShowcase(contentURL: URL)
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

        if configuration.shouldSimulateScreenshotShowcase,
           let contentURL = configuration.screenshotContentURL {
            return .simulateScreenshotShowcase(contentURL: contentURL)
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

    private static var hasStartedScreenshotShowcase = false

    static func startScreenshotShowcaseFlow(
        contentURL: URL,
        openDocumentsBurst: ([URL]) -> Void,
        focusDocument: (URL) -> Void,
        setDocumentViewMode: ((ReaderDocumentViewMode) -> Void)? = nil,
        presentWatchFolderSheet: ((URL, ReaderFolderWatchScope) -> Void)? = nil
    ) {
        guard !hasStartedScreenshotShowcase else { return }
        hasStartedScreenshotShowcase = true

        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minimark-screenshot-showcase", isDirectory: true)

        let subdirectories = [
            "project",
            "project/plans",
            "project/agents",
            "project/skills",
            "project/reviews",
            "project/docs"
        ]

        let fileMapping: [(subdirectory: String, name: String, daysAgo: Int)] = [
            ("project", "changelog.md", 1),
            ("project", "session-log.md", 0),
            ("project/plans", "auth-migration.md", 0),
            ("project/plans", "cache-redesign.md", 2),
            ("project/plans", "concurrency-migration.md", 1),
            ("project/agents", "code-reviewer.md", 5),
            ("project/agents", "test-writer.md", 4),
            ("project/skills", "refactor-skill.md", 6),
            ("project/skills", "security-review-skill.md", 7),
            ("project/reviews", "pr-847-review.md", 0),
            ("project/reviews", "security-audit.md", 3),
            ("project/docs", "architecture.md", 5),
            ("project/docs", "tool-reference.md", 3),
            ("project/docs", "performance-report.md", 1),
        ]

        do {
            if FileManager.default.fileExists(atPath: baseURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: baseURL)
            }

            for subdirectory in subdirectories {
                let directoryURL = baseURL.appendingPathComponent(subdirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            var fileURLs: [URL] = []
            for file in fileMapping {
                let sourceURL = contentURL.appendingPathComponent(file.name)
                let destinationURL = baseURL
                    .appendingPathComponent(file.subdirectory)
                    .appendingPathComponent(file.name)

                if FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                } else {
                    try "# \(file.name)\n".write(to: destinationURL, atomically: true, encoding: .utf8)
                }

                let modificationDate = Calendar.current.date(
                    byAdding: .day, value: -file.daysAgo, to: Date()
                ) ?? Date()
                try FileManager.default.setAttributes(
                    [.modificationDate: modificationDate],
                    ofItemAtPath: destinationURL.path(percentEncoded: false)
                )
                fileURLs.append(destinationURL)
            }

            openDocumentsBurst(fileURLs)

            // Select the active document: from env var if set, otherwise the last file
            let activeFileName = ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotActiveFileEnvironmentKey
            ]
            let targetURL: URL?
            if let activeFileName, !activeFileName.isEmpty {
                targetURL = fileURLs.first { $0.lastPathComponent == activeFileName }
            } else {
                targetURL = fileURLs.last
            }
            if let targetURL {
                focusDocument(targetURL)
            }

            // Set split view mode if requested
            if ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotSplitViewEnvironmentKey
            ] == "true" {
                setDocumentViewMode?(.split)
            }

            // Present watch folder sheet over loaded content if requested
            if let watchSheetPath = ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotShowWatchSheetEnvironmentKey
            ], !watchSheetPath.isEmpty {
                let watchURL = URL(fileURLWithPath: watchSheetPath, isDirectory: true)
                let scopeEnv = ProcessInfo.processInfo.environment[
                    ReaderUITestLaunchConfiguration.screenshotWatchScopeEnvironmentKey
                ]
                let scope: ReaderFolderWatchScope = scopeEnv == "includeSubfolders"
                    ? .includeSubfolders : .selectedFolderOnly
                presentWatchFolderSheet?(watchURL, scope)
            }
        } catch {
            #if DEBUG
            assertionFailure("Failed to start screenshot showcase flow: \(error)")
            #else
            NSLog("Failed to start screenshot showcase flow: \(error)")
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
