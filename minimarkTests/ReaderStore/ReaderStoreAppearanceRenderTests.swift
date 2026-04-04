import XCTest
@testable import minimark

@MainActor
final class ReaderStoreAppearanceRenderTests: XCTestCase {
    private let testAppearance = LockedAppearance(readerTheme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)

    func testSetAppearanceOverrideSetsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        XCTAssertFalse(fixture.store.needsAppearanceRender)

        fixture.store.setAppearanceOverride(testAppearance)

        XCTAssertTrue(fixture.store.needsAppearanceRender)
    }

    func testRenderWithAppearanceClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(testAppearance)
        XCTAssertTrue(fixture.store.needsAppearanceRender)

        try fixture.store.renderWithAppearance(testAppearance)

        XCTAssertFalse(fixture.store.needsAppearanceRender)
    }

    func testRenderCurrentMarkdownClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(testAppearance)
        XCTAssertTrue(fixture.store.needsAppearanceRender)

        try fixture.store.renderCurrentMarkdownImmediately()

        XCTAssertFalse(fixture.store.needsAppearanceRender)
    }
}
