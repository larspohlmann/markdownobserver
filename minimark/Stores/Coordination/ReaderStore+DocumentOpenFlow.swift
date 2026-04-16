import Foundation

extension ReaderStore {
    func openFile(at url: URL) {
        openFile(at: url, origin: .manual)
    }

    func openFile(
        at url: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        activateDeferredSetupIfNeeded()
        do {
            let accessibleURL = url
            let normalizedURL = Self.normalizedFileURL(accessibleURL)
            securityScopeResolver.activateFileSecurityScope(for: accessibleURL, reason: "open")
            if let folderWatchSession {
                setActiveFolderWatchSession(securityScopeResolver.normalizedFolderWatchSession(folderWatchSession))
            }
            let readURL = securityScopeResolver.effectiveAccessibleFileURL(
                for: normalizedURL, reason: "open", folderWatchSession: activeFolderWatchSession
            )
            document.currentOpenOrigin = origin

            let loaded = try loadMarkdownFile(at: readURL)

            // Stop previous file-watch callbacks before mutating the active
            // document identity so stale events cannot cross into the new file state.
            file.watcher.stopWatching()

            try presentLoadedDocument(
                loaded,
                at: normalizedURL,
                diffBaselineMarkdown: initialDiffBaselineMarkdown,
                resetDocumentViewMode: true,
                acknowledgeExternalChange: true
            )

            applyPostOpenSideEffects(
                accessibleURL: accessibleURL,
                normalizedURL: normalizedURL,
                origin: origin,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown,
                loadedMarkdown: loaded.markdown
            )
        } catch {
            handle(error)
        }
    }

    func materializeDeferredDocument(
        origin: ReaderOpenOrigin? = nil,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard documentLoadState == .deferred || documentLoadState == .loading,
              let url = fileURL else {
            return
        }

        if documentLoadState == .deferred {
            transitionToLoading()
        }

        openFile(
            at: url,
            origin: origin ?? document.currentOpenOrigin,
            folderWatchSession: folderWatchSession ?? activeFolderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )

        // Safety: if openFile failed internally, clear the loading state
        clearLoadingState()

        if initialDiffBaselineMarkdown != nil {
            noteObservedExternalChange(kind: .modified)
        }
    }
}
