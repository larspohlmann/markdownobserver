import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreAppearanceRenderTests {
    private let testAppearance = LockedAppearance(readerTheme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)

    @Test @MainActor func setAppearanceOverrideSetsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        #expect(!fixture.store.needsAppearanceRender)

        fixture.store.setAppearanceOverride(testAppearance)

        #expect(fixture.store.needsAppearanceRender)
    }

    @Test @MainActor func renderWithAppearanceClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(testAppearance)
        #expect(fixture.store.needsAppearanceRender)

        try fixture.store.renderWithAppearance(testAppearance)

        #expect(!fixture.store.needsAppearanceRender)
    }

    @Test @MainActor func renderCurrentMarkdownClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(testAppearance)
        #expect(fixture.store.needsAppearanceRender)

        try fixture.store.renderCurrentMarkdownImmediately()

        #expect(!fixture.store.needsAppearanceRender)
    }
}
