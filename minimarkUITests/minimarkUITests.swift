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

        let includeSubfoldersToggle = toggleElement(
            in: sheet,
            label: "Include subfolders"
        )
        XCTAssertTrue(includeSubfoldersToggle.waitForExistence(timeout: 2))
        if includeSubfoldersToggle.value as? String != "1" {
            includeSubfoldersToggle.tap()
        }

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

    private func makeTemporaryFolder() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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

    private func toggleElement(in sheet: XCUIElement, label: String) -> XCUIElement {
        let checkbox = sheet.checkBoxes[label]
        let toggleSwitch = sheet.switches[label]

        waitForCondition(timeout: 2.0) {
            checkbox.exists || toggleSwitch.exists
        }

        if checkbox.exists {
            return checkbox
        }

        return toggleSwitch
    }
}
