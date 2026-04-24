import Foundation
import Testing
@testable import minimark

@MainActor
private final class CapturingMarkdownRenderer: MarkdownRendering {
    var lastOverride: ThemeOverride?
    var renderCallCount = 0

    func render(
        markdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        theme: ThemeDefinition,
        syntaxTheme: SyntaxThemeKind,
        baseFontSize: Double,
        readerThemeOverride: ThemeOverride?
    ) throws -> RenderedMarkdown {
        lastOverride = readerThemeOverride
        renderCallCount += 1
        return RenderedMarkdown(
            htmlDocument: "<html></html>",
            changedRegions: changedRegions,
            renderedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

@MainActor
private func makeController(
    settings: TestSettingsStore,
    renderer: CapturingMarkdownRenderer
) -> RenderingController {
    let securityScopeResolver = SecurityScopeResolver(
        securityScope: TestSecurityScopeAccess(),
        settingsStore: settings,
        requestWatchedFolderReauthorization: { _ in nil }
    )
    return RenderingController(
        renderingDependencies: RenderingDependencies(
            renderer: renderer,
            differ: TestChangedRegionDiffer()
        ),
        settingsStore: settings,
        securityScopeResolver: securityScopeResolver
    )
}

@Suite @MainActor struct RenderingControllerOverrideTests {
    @Test func rendererReceivesSettingsOverrideWhenNoAppearanceOverride() throws {
        let settings = TestSettingsStore(autoRefreshOnExternalChange: true)
        settings.updateTheme(.nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)
        settings.updateReaderThemeOverride(override)
        let renderer = CapturingMarkdownRenderer()
        let controller = makeController(settings: settings, renderer: renderer)

        try controller.renderImmediately(
            sourceMarkdown: "# hi",
            changedRegions: [],
            unsavedChangedRegions: [],
            fileURL: nil,
            folderWatchSession: nil
        )

        #expect(renderer.renderCallCount == 1)
        #expect(renderer.lastOverride == override)
    }

    @Test func rendererReceivesAppearanceOverrideWhenAppearanceIsSet() throws {
        let settings = TestSettingsStore(autoRefreshOnExternalChange: true)
        settings.updateTheme(.nord)
        settings.updateReaderThemeOverride(
            ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)
        )
        let renderer = CapturingMarkdownRenderer()
        let controller = makeController(settings: settings, renderer: renderer)
        let appearanceOverride = ThemeOverride(themeKind: .dracula, backgroundHex: "#AABBCC", foregroundHex: "#DDEEFF")

        try controller.renderWithAppearance(
            LockedAppearance(
                readerTheme: .dracula,
                baseFontSize: 16,
                syntaxTheme: .monokai,
                readerThemeOverride: appearanceOverride
            ),
            sourceMarkdown: "# hi",
            changedRegions: [],
            unsavedChangedRegions: [],
            fileURL: nil,
            folderWatchSession: nil
        )

        #expect(renderer.lastOverride == appearanceOverride)
    }
}
