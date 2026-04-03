import XCTest
import Combine
@testable import minimark

@MainActor
final class WindowAppearanceControllerTests: XCTestCase {
    private var settingsStore: TestReaderSettingsStore!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        settingsStore = TestReaderSettingsStore(autoRefreshOnExternalChange: true)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        settingsStore = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func testInitialStateIsUnlockedWithGlobalSettings() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.effectiveTheme, .blackOnWhite)
        XCTAssertEqual(controller.effectiveFontSize, 15)
        XCTAssertEqual(controller.effectiveSyntaxTheme, .monokai)
    }

    // MARK: - Unlocked propagation

    func testUnlockedControllerPropagatesThemeChange() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        settingsStore.updateTheme(.newspaper)

        XCTAssertEqual(controller.effectiveTheme, .newspaper)
    }

    func testUnlockedControllerPropagatesFontSizeChange() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        settingsStore.updateBaseFontSize(24)

        XCTAssertEqual(controller.effectiveFontSize, 24)
    }

    func testUnlockedControllerPropagatesSyntaxThemeChange() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        settingsStore.updateSyntaxTheme(.dracula)

        XCTAssertEqual(controller.effectiveSyntaxTheme, .dracula)
    }

    // MARK: - Lock

    func testLockFreezesCurrentValues() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        settingsStore.updateTheme(.newspaper)
        settingsStore.updateBaseFontSize(20)
        settingsStore.updateSyntaxTheme(.nord)

        controller.lock()

        XCTAssertTrue(controller.isLocked)
        XCTAssertEqual(controller.effectiveTheme, .newspaper)
        XCTAssertEqual(controller.effectiveFontSize, 20)
        XCTAssertEqual(controller.effectiveSyntaxTheme, .nord)
    }

    func testLockedControllerIgnoresGlobalChanges() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        controller.lock()

        settingsStore.updateTheme(.greenTerminal)
        settingsStore.updateBaseFontSize(48)
        settingsStore.updateSyntaxTheme(.github)

        XCTAssertEqual(controller.effectiveTheme, .blackOnWhite)
        XCTAssertEqual(controller.effectiveFontSize, 15)
        XCTAssertEqual(controller.effectiveSyntaxTheme, .monokai)
    }

    // MARK: - Unlock

    func testUnlockDiscardsStoredStyleAndResumesGlobal() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        controller.lock()

        settingsStore.updateTheme(.newspaper)
        settingsStore.updateBaseFontSize(24)

        controller.unlock()

        XCTAssertFalse(controller.isLocked)
        XCTAssertEqual(controller.effectiveTheme, .newspaper)
        XCTAssertEqual(controller.effectiveFontSize, 24)
    }

    // MARK: - Restore

    func testRestoreAppliesLockedAppearanceAndLocks() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        let stored = LockedAppearance(readerTheme: .commodore64, baseFontSize: 22, syntaxTheme: .solarizedDark)

        controller.restore(from: stored)

        XCTAssertTrue(controller.isLocked)
        XCTAssertEqual(controller.effectiveTheme, .commodore64)
        XCTAssertEqual(controller.effectiveFontSize, 22)
        XCTAssertEqual(controller.effectiveSyntaxTheme, .solarizedDark)
    }

    func testRestoreIgnoresSubsequentGlobalChanges() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        let stored = LockedAppearance(readerTheme: .commodore64, baseFontSize: 22, syntaxTheme: .solarizedDark)
        controller.restore(from: stored)

        settingsStore.updateTheme(.focus)

        XCTAssertEqual(controller.effectiveTheme, .commodore64)
    }

    // MARK: - Locked appearance snapshot

    func testLockedAppearanceReturnsNilWhenUnlocked() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        XCTAssertNil(controller.lockedAppearance)
    }

    func testLockedAppearanceReturnsCapturedValuesWhenLocked() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        settingsStore.updateTheme(.newspaper)
        settingsStore.updateBaseFontSize(20)
        settingsStore.updateSyntaxTheme(.nord)
        controller.lock()

        let snapshot = controller.lockedAppearance
        XCTAssertEqual(snapshot?.readerTheme, .newspaper)
        XCTAssertEqual(snapshot?.baseFontSize, 20)
        XCTAssertEqual(snapshot?.syntaxTheme, .nord)
    }

    // MARK: - Locked window count

    func testLockedWindowCountIncrementsOnLock() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        let before = WindowAppearanceController.lockedWindowCount

        controller.lock()

        XCTAssertEqual(WindowAppearanceController.lockedWindowCount, before + 1)
    }

    func testLockedWindowCountDecrementsOnUnlock() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        controller.lock()
        let afterLock = WindowAppearanceController.lockedWindowCount

        controller.unlock()

        XCTAssertEqual(WindowAppearanceController.lockedWindowCount, afterLock - 1)
    }
}
