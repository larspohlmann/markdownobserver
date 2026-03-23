//
//  minimarkUITests.swift
//  minimarkUITests
//
//

import XCTest

final class minimarkUITests: XCTestCase {
    private let watchFolderSheetIdentifier = "folder-watch-sheet"
    private let cancelButtonIdentifier = "folder-watch-cancel-button"
    private let startButtonIdentifier = "folder-watch-start-button"
    private let previewSummaryIdentifier = "reader-preview-summary"
    private let uiTestModeArgument = "-minimark-ui-test"
    private let presentWatchFolderSheetArgument = "-minimark-present-watch-folder-sheet"
    private let autoStartWatchFolderArgument = "-minimark-auto-start-watch-folder"
    private let simulateAutoOpenWatchFlowArgument = "-minimark-simulate-auto-open-watch-flow"
    private let watchFolderPathEnvironmentKey = "MINIMARK_UI_TEST_WATCH_FOLDER_PATH"
    private let exclusionDialogTitle = "Optimize Large Folder Watch"
    private let reviewExclusionsButtonTitle = "Choose subdirectories to deactivate"
    private let deactivateAllButtonTitle = "Deactivate All"
    private let startWatchingAnywayButtonTitle = "Start Watching Anyway"
    private let dialogStartButtonIdentifier = "folder-watch-dialog-start-button"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWatchFolderSheetShowsDefaultStateAndCancels() throws {
        let folderURL = try makeTemporaryFolder()
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launch()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Watch Folder"].exists)
        XCTAssertTrue(app.staticTexts["When watch starts"].exists)
        XCTAssertTrue(app.staticTexts["Folder scope"].exists)
        XCTAssertTrue(app.staticTexts[folderURL.lastPathComponent].exists)

        let summaryCard = sheet.staticTexts["Watch summary"]
        XCTAssertTrue(summaryCard.exists)
        XCTAssertEqual(summaryCard.value as? String, "watchChangesOnly|selectedFolderOnly")

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
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testWatchedFolderAutoOpensNewMarkdownFileAndReflectsLaterEdit() throws {
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, simulateAutoOpenWatchFlowArgument]
        app.launch()

        let preview = app.descendants(matching: .any).matching(identifier: previewSummaryIdentifier).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        waitForElement(preview, valueContaining: "file=auto-open.md", timeout: 8)

        waitForElement(preview, valueNotContaining: "regions=0", timeout: 12)
        waitForElement(preview, valueContaining: "file=auto-open.md", timeout: 8)

        let previewValue = preview.value as? String
        XCTAssertNotNil(previewValue)
        XCTAssertFalse(previewValue?.contains("regions=0") ?? true)
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
        app.launch()

        let sheet = app.descendants(matching: .any).matching(identifier: watchFolderSheetIdentifier).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        selectIncludeSubfoldersSegment(in: sheet)

        let summaryCard = sheet.staticTexts["Watch summary"]
        XCTAssertTrue(summaryCard.exists)
        XCTAssertEqual(summaryCard.value as? String, "watchChangesOnly|includeSubfolders")

        sheet.buttons[startButtonIdentifier].tap()

        waitForCondition(timeout: 2) {
            app.descendants(matching: .any)
                .matching(identifier: self.watchFolderSheetIdentifier)
                .count == 0
        }

        let preview = app.descendants(matching: .any).matching(identifier: previewSummaryIdentifier).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        waitForElement(preview, valueContaining: "file=none", timeout: 3)
    }

    @MainActor
    func testFolderWatchThresholdFlowRequiresExclusionsThenEnablesStartWhenThresholdIsMet() throws {
        let folderURL = try makeTemporaryFolder(subdirectoryCount: 100)
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launch()

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

        let startAnywayButton = dialogPrimaryStartButton(in: dialogSheet)
        XCTAssertTrue(startAnywayButton.waitForExistence(timeout: 2))
        XCTAssertFalse(startAnywayButton.isEnabled)

        let deactivateAllButton = dialogSheet.buttons[deactivateAllButtonTitle]
        XCTAssertTrue(deactivateAllButton.waitForExistence(timeout: 4))
        deactivateAllButton.tap()

        waitForCondition(timeout: 6) {
            self.dialogPrimaryStartButton(in: dialogSheet).isEnabled
        }

        XCTAssertTrue(app.staticTexts["Threshold met"].exists)
    }

    @MainActor
    func testIncludeSubfoldersToggleKeepsSheetResponsiveAroundOptimizationCardStateChanges() throws {
        let folderURL = try makeTemporaryFolder(subdirectoryCount: 100)
        let app = XCUIApplication()
        app.launchArguments += [uiTestModeArgument, presentWatchFolderSheetArgument]
        app.launchEnvironment[watchFolderPathEnvironmentKey] = folderURL.path
        app.launch()

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

    private func waitForElement(_ element: XCUIElement, valueContaining substring: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "value CONTAINS %@", substring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed)
    }

    private func waitForElement(_ element: XCUIElement, valueNotContaining substring: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "NOT (value CONTAINS %@)", substring)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed)
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
