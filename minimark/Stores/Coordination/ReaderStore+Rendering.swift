import Foundation

extension ReaderStore {
    func scheduleDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: Self.draftPreviewRenderDebounceInterval)

            guard !Task.isCancelled else {
                return
            }

            self.pendingDraftPreviewRenderTask = nil

            do {
                try self.renderCurrentMarkdownImmediately()
                self.identity.lastError = nil
            } catch {
                self.handle(error)
            }
        }
    }

    func cancelPendingDraftPreviewRender() {
        pendingDraftPreviewRenderTask?.cancel()
        pendingDraftPreviewRenderTask = nil
    }

    func renderCurrentMarkdownImmediately() throws {
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        content.lastRefreshAt = Date()
    }

    func renderWithAppearance(_ appearance: LockedAppearance) throws {
        appearanceOverride = appearance
        cancelPendingDraftPreviewRender()
        try renderCurrentMarkdown()
        needsAppearanceRender = false
        content.lastRefreshAt = Date()
    }

    func setAppearanceOverride(_ appearance: LockedAppearance) {
        appearanceOverride = appearance
        needsAppearanceRender = true
    }

    func clearAppearanceOverride() {
        appearanceOverride = nil
        needsAppearanceRender = false
    }

    private func renderCurrentMarkdown() throws {
        let settings = settingsStore.currentSettings
        let effectiveThemeKind = appearanceOverride?.readerTheme ?? settings.readerTheme
        let effectiveFontSize = appearanceOverride?.baseFontSize ?? settings.baseFontSize
        let effectiveSyntaxTheme = appearanceOverride?.syntaxTheme ?? settings.syntaxTheme
        let theme = effectiveThemeKind.themeDefinition

        let docDir = fileURL?.deletingLastPathComponent()
        securityScopeResolver.activateTrustedImageFolderAccessIfNeeded(
            for: docDir, folderWatchSession: activeFolderWatchSession
        )

        let imageResult = MarkdownImageResolver.resolve(
            markdown: sourceMarkdown,
            documentDirectoryURL: docDir
        )

        identity.needsImageDirectoryAccess = imageResult.needsDirectoryAccess

        let rendered = try rendering.renderer.render(
            markdown: imageResult.markdown,
            changedRegions: changedRegions,
            unsavedChangedRegions: unsavedChangedRegions,
            theme: theme,
            syntaxTheme: effectiveSyntaxTheme,
            baseFontSize: effectiveFontSize
        )

        content.renderedHTMLDocument = rendered.htmlDocument
        needsAppearanceRender = false
    }
}
