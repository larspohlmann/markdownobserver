import Foundation
import Observation

@MainActor
@Observable
final class ReaderRenderingController {
    static let draftPreviewRenderDebounceInterval: Duration = .milliseconds(5)

    var renderedHTMLDocument: String = ""
    var lastRefreshAt: Date?
    var needsAppearanceRender = false
    var needsImageDirectoryAccess: Bool = false

    @ObservationIgnored var appearanceOverride: LockedAppearance?
    @ObservationIgnored var pendingDraftPreviewRenderTask: Task<Void, Never>?

    private let renderingDependencies: ReaderRenderingDependencies
    private let settingsStore: ReaderSettingsStoring
    private let securityScopeResolver: SecurityScopeResolver

    init(
        renderingDependencies: ReaderRenderingDependencies,
        settingsStore: ReaderSettingsStoring,
        securityScopeResolver: SecurityScopeResolver
    ) {
        self.renderingDependencies = renderingDependencies
        self.settingsStore = settingsStore
        self.securityScopeResolver = securityScopeResolver
    }

    func renderImmediately(
        sourceMarkdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        fileURL: URL?,
        folderWatchSession: ReaderFolderWatchSession?
    ) throws {
        cancelPendingDraftPreviewRender()
        try renderMarkdown(
            sourceMarkdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            fileURL: fileURL,
            folderWatchSession: folderWatchSession
        )
        lastRefreshAt = Date()
    }

    func renderWithAppearance(
        _ appearance: LockedAppearance,
        sourceMarkdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        fileURL: URL?,
        folderWatchSession: ReaderFolderWatchSession?
    ) throws {
        appearanceOverride = appearance
        cancelPendingDraftPreviewRender()
        try renderMarkdown(
            sourceMarkdown: sourceMarkdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            fileURL: fileURL,
            folderWatchSession: folderWatchSession
        )
        needsAppearanceRender = false
        lastRefreshAt = Date()
    }

    func scheduleDraftPreviewRender(
        sourceMarkdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        fileURL: URL?,
        folderWatchSession: ReaderFolderWatchSession?
    ) {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.draftPreviewRenderDebounceInterval)
            guard !Task.isCancelled else { return }
            self.pendingDraftPreviewRenderTask = nil
            try? self.renderImmediately(
                sourceMarkdown: sourceMarkdown,
                changedRegions: changedRegions,
                unsavedChangedRegions: unsavedChangedRegions,
                fileURL: fileURL,
                folderWatchSession: folderWatchSession
            )
        }
    }

    func cancelPendingDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = nil
    }

    func setAppearanceOverride(_ appearance: LockedAppearance) {
        appearanceOverride = appearance
        needsAppearanceRender = true
    }

    func clearAppearanceOverride() {
        appearanceOverride = nil
        needsAppearanceRender = false
    }

    func computeChangedRegions(
        diffBaselineMarkdown: String?,
        newMarkdown: String
    ) -> [ChangedRegion] {
        guard let diffBaselineMarkdown else { return [] }
        return renderingDependencies.differ.computeChangedRegions(
            oldMarkdown: diffBaselineMarkdown,
            newMarkdown: newMarkdown
        )
    }

    // MARK: - Private

    private func renderMarkdown(
        sourceMarkdown: String,
        changedRegions: [ChangedRegion],
        unsavedChangedRegions: [ChangedRegion],
        fileURL: URL?,
        folderWatchSession: ReaderFolderWatchSession?
    ) throws {
        let settings = settingsStore.currentSettings
        let effectiveThemeKind = appearanceOverride?.readerTheme ?? settings.readerTheme
        let effectiveFontSize = appearanceOverride?.baseFontSize ?? settings.baseFontSize
        let effectiveSyntaxTheme = appearanceOverride?.syntaxTheme ?? settings.syntaxTheme
        let theme = effectiveThemeKind.themeDefinition

        let docDir = fileURL?.deletingLastPathComponent()
        securityScopeResolver.activateTrustedImageFolderAccessIfNeeded(
            for: docDir, folderWatchSession: folderWatchSession
        )

        let imageResult = MarkdownImageResolver.resolve(
            markdown: sourceMarkdown,
            documentDirectoryURL: docDir
        )

        needsImageDirectoryAccess = imageResult.needsDirectoryAccess

        let rendered = try renderingDependencies.renderer.render(
            markdown: imageResult.markdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            theme: theme,
            syntaxTheme: effectiveSyntaxTheme,
            baseFontSize: effectiveFontSize
        )

        renderedHTMLDocument = rendered.htmlDocument
        needsAppearanceRender = false
    }
}
