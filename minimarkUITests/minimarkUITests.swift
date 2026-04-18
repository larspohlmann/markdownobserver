//
//  minimarkUITests.swift
//  minimarkUITests
//
//

import XCTest

final class minimarkUITests: XCTestCase {
    private let watchFolderSheetIdentifier = AccessibilityID.folderWatchSheet.rawValue
    private let cancelButtonIdentifier = AccessibilityID.folderWatchCancelButton.rawValue
    private let startButtonIdentifier = AccessibilityID.folderWatchStartButton.rawValue
    private let previewSummaryIdentifier = AccessibilityID.previewSummary.rawValue
    private let uiTestModeArgument = "-minimark-ui-test"
    private let presentWatchFolderSheetArgument = "-minimark-present-watch-folder-sheet"
    private let autoStartWatchFolderArgument = "-minimark-auto-start-watch-folder"
    private let simulateAutoOpenWatchFlowArgument = "-minimark-simulate-auto-open-watch-flow"
    private let watchFolderPathEnvironmentKey = "MINIMARK_UI_TEST_WATCH_FOLDER_PATH"
    private let exclusionDialogTitle = "Optimize Large Folder Watch"
    private let reviewExclusionsButtonTitle = "Choose subdirectories to deactivate"
    private let deactivateAllButtonTitle = "Deactivate All"
    private let startWatchingAnywayButtonTitle = "Start Watching Anyway"
    private let dialogStartButtonIdentifier = AccessibilityID.folderWatchDialogStartButton.rawValue
    private let sidebarGroupToggleIdentifier = AccessibilityID.sidebarGroupToggle.rawValue
    private let sidebarColumnIdentifier = AccessibilityID.sidebarColumn.rawValue
    private let simulateGroupedSidebarArgument = "-minimark-simulate-grouped-sidebar"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWatchFolderSheetShowsDefaultStateAndCancels() throws {
        let folderURL = try makeTemporaryFolder()
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launchSandboxed()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Watch Folder"].exists)
        XCTAssertTrue(app.staticTexts["On start"].exists)
        XCTAssertTrue(app.staticTexts["Scope"].exists)
        XCTAssertTrue(app.staticTexts[folderURL.lastPathComponent].exists)

        let startButton = sheet.buttons[startButtonIdentifier]
        XCTAssertTrue(startButton.exists)
        XCTAssertTrue(startButton.isEnabled)

        let cancelButton = sheet.buttons[cancelButtonIdentifier]
        XCTAssertTrue(cancelButton.exists)
        cancelButton.tap()

        waitForCondition(timeout: 1) {
            app.descendants(matching: .any)
                .matching(identifier: self.watchFolderSheetIdentifier)
                .count == 0
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launchSandboxed()
        }
    }

    // Regression for #384: `@FocusedValue`-gated menu commands (Watch Folder,
    // Edit Source, Table of Contents, etc.) were all disabled on cold launch
    // because `focusedValue` requires a focused descendant. They must be
    // published as `focusedSceneValue` so they're available whenever the
    // window is key, regardless of which view has keyboard focus.
    //
    // Uses the standard `uiTestModeArgument` launch flag; the UI-test bootstrap
    // path (`UITestWindowBootstrapper` / `HostedWindowController`) opens a real
    // `WindowGroup` window so the test exercises the same SwiftUI Scene path
    // production uses.
    @MainActor
    func testFocusedSceneCommandsAreEnabledWhenWindowIsKey() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument]
        app.launchSandboxed()

        // Wait for the real WindowGroup scene window to be up — the off-screen
        // bootstrap window also matches `app.windows.firstMatch`, so gate on a
        // marker that only `ContentView` (inside the scene) renders.
        let previewSummary = app.descendants(matching: .any)
            .matching(identifier: previewSummaryIdentifier).firstMatch
        XCTAssertTrue(previewSummary.waitForExistence(timeout: 10))

        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 2))
        fileMenu.click()

        let watchMenuItem = fileMenu.menuItems["Watch Folder..."]
        XCTAssertTrue(watchMenuItem.waitForExistence(timeout: 2))
        pollUntilEnabled(watchMenuItem, timeout: 2)
        XCTAssertTrue(
            watchMenuItem.isEnabled,
            "File → Watch Folder... must be enabled when a window is key"
        )

        fileMenu.click()

        let watchMenu = app.menuBars.menuBarItems["Watch"]
        XCTAssertTrue(watchMenu.waitForExistence(timeout: 2))
        watchMenu.click()

        let watchFolderInWatchMenu = watchMenu.menuItems["Watch Folder..."]
        XCTAssertTrue(watchFolderInWatchMenu.waitForExistence(timeout: 2))
        pollUntilEnabled(watchFolderInWatchMenu, timeout: 2)
        XCTAssertTrue(
            watchFolderInWatchMenu.isEnabled,
            "Watch → Watch Folder... must be enabled when a window is key"
        )
    }

    private func pollUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !element.isEnabled {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor
    func testWatchedFolderAutoOpensNewMarkdownFileAndReflectsLaterEdit() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateAutoOpenWatchFlowArgument]
        app.launchSandboxed()

        let preview = app.descendants(matching: .any).matching(identifier: previewSummaryIdentifier).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        waitForPreviewSummary(preview, matching: { $0.fileName == "auto-open.md" }, timeout: 8)

        waitForPreviewSummary(preview, matching: { $0.regionCount > 0 }, timeout: 12)
        waitForPreviewSummary(preview, matching: { $0.fileName == "auto-open.md" }, timeout: 8)

        let parsed = currentPreviewSummary(preview)
        XCTAssertNotNil(parsed)
        XCTAssertGreaterThan(parsed?.regionCount ?? 0, 0)
    }

    @MainActor
    func testWatchChangesOnlyWithIncludedSubfoldersDoesNotAutoOpenExistingMarkdownFiles() throws {
        let folderURL = try makeTemporaryFolder()
        let nestedFolderURL = folderURL
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolderURL, withIntermediateDirectories: true)

        let topLevelFileURL = folderURL.appendingPathComponent("top-level.md")
        let nestedFileURL = nestedFolderURL.appendingPathComponent("existing.md")
        try "# Top Level".write(to: topLevelFileURL, atomically: true, encoding: .utf8)
        try "# Nested".write(to: nestedFileURL, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launchSandboxed()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        selectIncludeSubfoldersSegment(in: sheet)

        sheet.buttons[startButtonIdentifier].tap()

        waitForCondition(timeout: 2) {
            app.descendants(matching: .any)
                .matching(identifier: self.watchFolderSheetIdentifier)
                .count == 0
        }

        let preview = app.descendants(matching: .any).matching(identifier: previewSummaryIdentifier).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        waitForPreviewSummary(preview, matching: { $0.fileName == "none" }, timeout: 3)
    }

    @MainActor
    func testFolderWatchThresholdFlowRequiresExclusionsThenEnablesStartWhenThresholdIsMet() throws {
        let folderURL = try makeTemporaryFolder(subdirectoryCount: 300)
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launchSandboxed()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        selectIncludeSubfoldersSegment(in: sheet)

        XCTAssertTrue(sheet.staticTexts["Action required before watch can start"].waitForExistence(timeout: 8))
        XCTAssertTrue(sheet.buttons[startButtonIdentifier].exists)
        XCTAssertFalse(sheet.buttons[startButtonIdentifier].isEnabled)

        let warningButton = sheet.buttons[reviewExclusionsButtonTitle]
        XCTAssertTrue(warningButton.waitForExistence(timeout: 8))
        warningButton.tap()

        let dialogTitle = app.staticTexts[exclusionDialogTitle]
        XCTAssertTrue(dialogTitle.waitForExistence(timeout: 6))
        let dialogSheet = app.sheets.containing(.staticText, identifier: exclusionDialogTitle).firstMatch
        XCTAssertTrue(dialogSheet.exists)

        let deactivateAllButton = dialogSheet.buttons[deactivateAllButtonTitle]
        XCTAssertTrue(deactivateAllButton.waitForExistence(timeout: 2))
        deactivateAllButton.tap()

        let startAnywayButton = dialogPrimaryStartButton(in: dialogSheet)
        XCTAssertTrue(startAnywayButton.waitForExistence(timeout: 2))
        waitForCondition(timeout: 6) {
            self.dialogPrimaryStartButton(in: dialogSheet).isEnabled
        }

        XCTAssertTrue(app.staticTexts["Threshold met"].exists)
    }

    @MainActor
    func testIncludeSubfoldersToggleKeepsSheetResponsiveAroundOptimizationCardStateChanges() throws {
        let folderURL = try makeTemporaryFolder(subdirectoryCount: 300)
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launchSandboxed()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        for _ in 0..<3 {
            selectIncludeSubfoldersSegment(in: sheet)
            XCTAssertTrue(sheet.staticTexts["Action required before watch can start"].waitForExistence(timeout: 8))
            XCTAssertTrue(sheet.buttons[reviewExclusionsButtonTitle].exists)

            selectSelectedFolderOnlySegment(in: sheet)
            XCTAssertTrue(sheet.buttons[startButtonIdentifier].waitForExistence(timeout: 3))
            XCTAssertTrue(sheet.buttons[startButtonIdentifier].isEnabled)
        }
    }

    // MARK: - Grouped Sidebar

    @MainActor
    func testGroupedSidebarShowsDocumentsFromMultipleSubdirectories() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateGroupedSidebarArgument]
        app.launchSandboxed()

        let groupToggles = app.buttons.matching(identifier: sidebarGroupToggleIdentifier)
        waitForCondition(timeout: 8) {
            groupToggles.count >= 3
        }

        XCTAssertGreaterThanOrEqual(groupToggles.count, 3, "Should have at least 3 folder groups")

        let groupPredicate = NSPredicate(
            format: "identifier == %@ AND (value CONTAINS[c] 'project' OR value CONTAINS[c] 'docs' OR value CONTAINS[c] 'plans')",
            sidebarGroupToggleIdentifier
        )
        let groupHeaders = app.buttons.matching(groupPredicate)
        XCTAssertGreaterThanOrEqual(groupHeaders.count, 2, "Should show disambiguated folder group headers")

        waitForCondition(timeout: 8) {
            app.staticTexts["README.md"].exists
        }
        XCTAssertTrue(app.staticTexts["README.md"].exists, "README.md should be visible in sidebar")

        waitForCondition(timeout: 8) {
            app.staticTexts["BUILDING.md"].exists
        }
        XCTAssertTrue(app.staticTexts["BUILDING.md"].exists, "BUILDING.md should be visible in sidebar")
    }

    @MainActor
    func testGroupedSidebarExposesCustomGroupToggleButtons() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateGroupedSidebarArgument]
        app.launchSandboxed()

        let customToggle = app.buttons.matching(identifier: sidebarGroupToggleIdentifier).firstMatch
        XCTAssertTrue(customToggle.waitForExistence(timeout: 8), "Grouped sidebar should expose custom group toggle buttons")
    }

    // MARK: - Group Drag-and-Drop Reordering

    @MainActor
    func testGroupedSidebarDisplaysExpectedGroupsInOrder() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateGroupedSidebarArgument]
        app.launchSandboxed()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Window should appear")

        let groupToggles = app.buttons.matching(identifier: sidebarGroupToggleIdentifier)
        waitForCondition(timeout: 10) {
            groupToggles.count >= 3
        }

        let plansToggle = groupToggles.matching(NSPredicate(format: "value == 'plans'")).firstMatch
        let projectToggle = groupToggles.matching(NSPredicate(format: "value == 'project'")).firstMatch
        let docsToggle = groupToggles.matching(NSPredicate(format: "value == 'docs'")).firstMatch
        XCTAssertTrue(plansToggle.exists, "Plans group should exist")
        XCTAssertTrue(projectToggle.exists, "Project group should exist")
        XCTAssertTrue(docsToggle.exists, "Docs group should exist")

        // Verify groups are displayed top-to-bottom in the sidebar
        XCTAssertLessThan(
            plansToggle.frame.origin.y,
            projectToggle.frame.origin.y,
            "Plans group should be above project group"
        )
        XCTAssertLessThan(
            projectToggle.frame.origin.y,
            docsToggle.frame.origin.y,
            "Project group should be above docs group"
        )
    }

    // MARK: - Sidebar Width Stability

    @MainActor
    func testSidebarWidthRemainsStableWhenWindowIsResized() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateGroupedSidebarArgument]
        app.launchSandboxed()

        let sidebar = app.scrollViews.matching(identifier: sidebarColumnIdentifier).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 8), "Sidebar should appear")

        waitForCondition(timeout: 8) {
            app.staticTexts["README.md"].exists
        }

        let window = app.windows.firstMatch

        // Wait for sidebar layout to stabilize
        waitForCondition(timeout: 5) {
            sidebar.frame.width > 100
        }

        let initialSidebarWidth = sidebar.frame.width
        let initialWindowWidth = window.frame.width

        // Drag right edge of window 300px wider
        let rightEdge = window.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
        let expandTarget = rightEdge.withOffset(CGVector(dx: 300, dy: 0))
        rightEdge.click(forDuration: 0.1, thenDragTo: expandTarget)

        // Wait for window to have expanded
        waitForCondition(timeout: 3) {
            window.frame.width > initialWindowWidth + 100
        }

        let expandedWindowWidth = window.frame.width
        XCTAssertGreaterThan(
            expandedWindowWidth, initialWindowWidth + 100,
            "Window should have expanded (was \(initialWindowWidth), now \(expandedWindowWidth))"
        )

        let sidebarAfterExpand = sidebar.frame.width
        XCTAssertEqual(
            initialSidebarWidth, sidebarAfterExpand, accuracy: 5.0,
            "Sidebar width must not change when window expands " +
            "(was \(initialSidebarWidth), became \(sidebarAfterExpand))"
        )
    }

    // MARK: - Helpers

    private func makeTemporaryFolder() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeTemporaryFolder(subdirectoryCount: Int) throws -> URL {
        let directoryURL = try makeTemporaryFolder()

        for index in 0..<subdirectoryCount {
            let childDirectoryURL = directoryURL
                .appendingPathComponent("subfolder-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: childDirectoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func currentPreviewSummary(_ element: XCUIElement) -> PreviewAccessibilitySummary? {
        guard let raw = element.value as? String else { return nil }
        return PreviewAccessibilitySummary(rawValue: raw)
    }

    private func waitForPreviewSummary(
        _ element: XCUIElement,
        matching predicate: @escaping (PreviewAccessibilitySummary) -> Bool,
        timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let summary = currentPreviewSummary(element), predicate(summary) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTFail(
            "Preview summary did not match within \(timeout)s (last value: \(String(describing: element.value)))"
        )
    }

    private func waitForCondition(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTFail("Condition not met within \(timeout) seconds")
    }

    private func selectIncludeSubfoldersSegment(in sheet: XCUIElement) {
        let directButton = sheet.buttons["Include Subfolders"]
        if directButton.exists || directButton.waitForExistence(timeout: 1.5) {
            directButton.tap()
            return
        }

        let directLowercaseButton = sheet.buttons["Include subfolders"]
        if directLowercaseButton.exists || directLowercaseButton.waitForExistence(timeout: 1.0) {
            directLowercaseButton.tap()
            return
        }

        let directRadio = sheet.radioButtons["Include Subfolders"]
        if directRadio.exists || directRadio.waitForExistence(timeout: 1.0) {
            directRadio.tap()
            return
        }

        let predicate = NSPredicate(format: "label CONTAINS[c] 'include subfolders'")
        let fallback = sheet.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 2.0))
        fallback.tap()
    }

    private func selectSelectedFolderOnlySegment(in sheet: XCUIElement) {
        let directButton = sheet.buttons["Selected Folder"]
        if directButton.exists || directButton.waitForExistence(timeout: 1.5) {
            directButton.tap()
            return
        }

        let directRadio = sheet.radioButtons["Selected Folder"]
        if directRadio.exists || directRadio.waitForExistence(timeout: 1.0) {
            directRadio.tap()
            return
        }

        let predicate = NSPredicate(format: "label CONTAINS[c] 'selected folder'")
        let fallback = sheet.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 2.0))
        fallback.tap()
    }

    private func dialogPrimaryStartButton(in container: XCUIElement) -> XCUIElement {
        container.buttons[dialogStartButtonIdentifier]
    }
}
