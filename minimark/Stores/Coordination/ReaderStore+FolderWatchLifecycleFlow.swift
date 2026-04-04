import Foundation

extension ReaderStore {
    func startWatchingFolder(folderURL: URL, options: ReaderFolderWatchOptions) {
        do {
            prepareForFolderWatchStart()

            let accessibleFolderURL = folderURL
            let normalizedOptions = options.encodedForFolder(accessibleFolderURL)
            let session = try activateFolderWatch(
                folderURL: accessibleFolderURL,
                options: normalizedOptions
            )

            finishStartingFolderWatch(session, accessibleFolderURL: accessibleFolderURL)
            try performInitialFolderWatchAutoOpenIfNeeded(
                folderURL: accessibleFolderURL,
                session: session
            )
        } catch {
            resetFolderWatchState(notifyIfNeeded: false)
            handle(error)
        }
    }

    func stopWatchingFolder() {
        let hadActiveFolderWatch = activeFolderWatchSession != nil
        resetFolderWatchState(notifyIfNeeded: hadActiveFolderWatch)

        if fileURL != nil {
            startWatchingCurrentFile()
        }
    }

    private func prepareForFolderWatchStart() {
        stopWatchingFolder()
        setFolderWatchAutoOpenWarning(nil)
        pendingFileSelectionRequest = nil
        folderWatchAutoOpenPlanner.resetTransientState()
        folderWatchAutoOpenPlanner.updateMinimumDiffBaselineAge(
            settingsStore.currentSettings.diffBaselineLookback.timeInterval
        )
    }

    private func activateFolderWatch(
        folderURL: URL,
        options: ReaderFolderWatchOptions
    ) throws -> ReaderFolderWatchSession {
        scopeContext.folderToken = securityScope.beginAccess(to: folderURL)

        try folderWatcher.startWatching(
            folderURL: folderURL,
            includeSubfolders: options.scope == .includeSubfolders,
            excludedSubdirectoryURLs: options.resolvedExcludedSubdirectoryURLs(relativeTo: folderURL)
        ) { [weak self] changedMarkdownEvents in
            guard let self else {
                return
            }

            Task { @MainActor [self] in
                self.handleObservedWatchedFolderChanges(changedMarkdownEvents)
            }
        }

        let session = ReaderFolderWatchSession(
            folderURL: Self.normalizedFileURL(folderURL),
            options: options,
            startedAt: .now
        )
        setActiveFolderWatchSession(session)
        return session
    }

    private func finishStartingFolderWatch(
        _ session: ReaderFolderWatchSession,
        accessibleFolderURL: URL
    ) {
        settingsStore.addRecentWatchedFolder(accessibleFolderURL, options: session.options)
        onFolderWatchStarted?(session)
        setLastWatchedFolderEventAt(nil)

        if fileURL != nil {
            startWatchingCurrentFile()
        }
    }

    private func performInitialFolderWatchAutoOpenIfNeeded(
        folderURL: URL,
        session: ReaderFolderWatchSession
    ) throws {
        guard session.options.openMode == .openAllMarkdownFiles else {
            return
        }

        let markdownURLs = try folderWatcher.markdownFiles(
            in: folderURL,
            includeSubfolders: session.options.scope == .includeSubfolders,
            excludedSubdirectoryURLs: session.options.resolvedExcludedSubdirectoryURLs(relativeTo: folderURL)
        )

        if markdownURLs.count > ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount {
            pendingFileSelectionRequest = ReaderFolderWatchFileSelectionRequest(
                folderURL: session.folderURL,
                session: session,
                allFileURLs: markdownURLs
            )
            return
        }

        pendingFileSelectionRequest = nil

        let initialPlan = initialFolderWatchAutoOpenPlan(
            markdownURLs: markdownURLs,
            session: session
        )

        setFolderWatchAutoOpenWarning(initialPlan.warning)
        openInitialMarkdownFilesFromWatchedFolder(initialPlan.autoOpenEvents, session: session)
    }

    private func initialFolderWatchAutoOpenPlan(
        markdownURLs: [URL],
        session: ReaderFolderWatchSession
    ) -> ReaderFolderWatchAutoOpenPlan {
        let initialMarkdownEvents = markdownURLs.map {
            ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
        }

        return folderWatchAutoOpenPlanner.initialPlan(
            for: initialMarkdownEvents,
            activeSession: session,
            currentDocumentFileURL: fileURLForCurrentDocument
        )
    }

    private func resetFolderWatchState(notifyIfNeeded: Bool) {
        folderWatcher.stopWatching()
        folderWatchAutoOpenPlanner.resetTransientState()
        pendingFileSelectionRequest = nil
        scopeContext.folderToken?.endAccess()
        scopeContext.folderToken = nil
        setActiveFolderWatchSession(nil)
        setLastWatchedFolderEventAt(nil)
        setFolderWatchAutoOpenWarning(nil)

        if notifyIfNeeded {
            onFolderWatchStopped?()
        }
    }
}
