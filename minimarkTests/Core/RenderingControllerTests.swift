import Testing
@testable import minimark

@MainActor
@Suite("RenderingController")
struct RenderingControllerTests {
    private func makeSUT(
        renderer: MarkdownRendering = TestMarkdownRenderer(),
        differ: ChangedRegionDiffering = TestChangedRegionDiffer()
    ) -> RenderingController {
        let settings = TestSettingsStore(autoRefreshOnExternalChange: true)
        let securityScope = SecurityScopeResolver(
            securityScope: TestSecurityScopeAccess(),
            settingsStore: settings,
            requestWatchedFolderReauthorization: { _ in nil }
        )
        return RenderingController(
            renderingDependencies: RenderingDependencies(renderer: renderer, differ: differ),
            settingsStore: settings,
            securityScopeResolver: securityScope
        )
    }

    @Test("renderImmediately produces HTML and sets lastRefreshAt")
    func renderImmediatelyProducesHTML() throws {
        let sut = makeSUT()
        try sut.renderImmediately(
            sourceMarkdown: "# Hello",
            changedRegions: [],
            unsavedChangedRegions: [],
            fileURL: nil,
            folderWatchSession: nil
        )
        #expect(sut.renderedHTMLDocument.contains("Hello"))
        #expect(sut.lastRefreshAt != nil)
    }

    @Test("setAppearanceOverride sets needsAppearanceRender")
    func setAppearanceOverrideSetsFlag() {
        let sut = makeSUT()
        sut.setAppearanceOverride(LockedAppearance(
            readerTheme: .blackOnWhite,
            baseFontSize: 16,
            syntaxTheme: .github
        ))
        #expect(sut.needsAppearanceRender)
        #expect(sut.appearanceOverride != nil)
    }

    @Test("clearAppearanceOverride clears override and flag")
    func clearAppearanceOverrideClearsState() {
        let sut = makeSUT()
        sut.setAppearanceOverride(LockedAppearance(
            readerTheme: .blackOnWhite,
            baseFontSize: 16,
            syntaxTheme: .github
        ))
        sut.clearAppearanceOverride()
        #expect(!sut.needsAppearanceRender)
        #expect(sut.appearanceOverride == nil)
    }

    @Test("computeChangedRegions returns empty for identical markdown")
    func computeChangedRegionsIdentical() {
        let sut = makeSUT()
        let regions = sut.computeChangedRegions(
            diffBaselineMarkdown: "# Hello",
            newMarkdown: "# Hello"
        )
        #expect(regions.isEmpty)
    }

    @Test("computeChangedRegions returns empty when baseline is nil")
    func computeChangedRegionsNilBaseline() {
        let sut = makeSUT()
        let regions = sut.computeChangedRegions(
            diffBaselineMarkdown: nil,
            newMarkdown: "# Hello"
        )
        #expect(regions.isEmpty)
    }

    @Test("cancelPendingDraftPreviewRender clears task")
    func cancelPendingDraftPreviewRender() {
        let sut = makeSUT()
        sut.cancelPendingDraftPreviewRender()
        #expect(sut.pendingDraftPreviewRenderTask == nil)
    }
}
