import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderStoreAppearanceRenderTests {

    @Test @MainActor func setAppearanceOverrideSetsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        #expect(!fixture.store.needsAppearanceRender)

        fixture.store.setAppearanceOverride(
            theme: .newspaper,
            baseFontSize: 20,
            syntaxTheme: .nord
        )

        #expect(fixture.store.needsAppearanceRender)
    }

    @Test @MainActor func renderWithAppearanceClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(
            theme: .newspaper,
            baseFontSize: 20,
            syntaxTheme: .nord
        )
        #expect(fixture.store.needsAppearanceRender)

        try fixture.store.renderWithAppearance(
            theme: .newspaper,
            baseFontSize: 20,
            syntaxTheme: .nord
        )

        #expect(!fixture.store.needsAppearanceRender)
    }

    @Test @MainActor func renderCurrentMarkdownClearsNeedsAppearanceRender() throws {
        let fixture = try ReaderStoreTestFixture(autoRefreshOnExternalChange: true)
        defer { fixture.cleanup() }

        fixture.store.openFile(at: fixture.primaryFileURL)

        fixture.store.setAppearanceOverride(
            theme: .newspaper,
            baseFontSize: 20,
            syntaxTheme: .nord
        )
        #expect(fixture.store.needsAppearanceRender)

        try fixture.store.renderCurrentMarkdownImmediately()

        #expect(!fixture.store.needsAppearanceRender)
    }
}
