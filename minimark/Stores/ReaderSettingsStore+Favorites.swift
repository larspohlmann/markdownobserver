import Foundation

extension ReaderSettingsStore {
    func addFavoriteWatchedFolder(
        name: String,
        folderURL: URL,
        options: ReaderFolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
        workspaceState: ReaderFavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )
    ) {
        updateSettings { settings in
            settings.favoriteWatchedFolders = ReaderFavoriteHistory.insertingUniqueFavorite(
                name: name,
                folderURL: folderURL,
                options: options,
                openDocumentFileURLs: openDocumentFileURLs,
                workspaceState: workspaceState,
                into: settings.favoriteWatchedFolders
            )
        }
    }

    func removeFavoriteWatchedFolder(id: UUID) {
        updateSettings { settings in
            settings.favoriteWatchedFolders = ReaderFavoriteHistory.removingFavorite(
                id: id,
                from: settings.favoriteWatchedFolders
            )
        }
    }

    func renameFavoriteWatchedFolder(id: UUID, newName: String) {
        updateSettings { settings in
            settings.favoriteWatchedFolders = ReaderFavoriteHistory.renamingFavorite(
                id: id,
                newName: newName,
                in: settings.favoriteWatchedFolders
            )
        }
    }

    func updateFavoriteWatchedFolderOpenDocuments(
        id: UUID,
        folderURL: URL,
        openDocumentFileURLs: [URL]
    ) {
        updateSettings(coalescePersistence: true) { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
                return
            }

            let existing = settings.favoriteWatchedFolders[index]
            let scopedRelativePaths = ReaderFavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
                from: openDocumentFileURLs,
                relativeTo: folderURL,
                options: existing.options
            )
            guard existing.openDocumentRelativePaths != scopedRelativePaths else {
                return
            }

            let updatedKnownPaths = Array(
                Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
            ).sorted()

            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existing.id,
                name: existing.name,
                folderPath: existing.folderPath,
                options: existing.options,
                bookmarkData: existing.bookmarkData,
                openDocumentRelativePaths: scopedRelativePaths,
                allKnownRelativePaths: updatedKnownPaths,
                workspaceState: existing.workspaceState,
                createdAt: existing.createdAt
            )
        }
    }

    func updateFavoriteWatchedFolderKnownDocuments(
        id: UUID,
        folderURL: URL,
        knownDocumentFileURLs: [URL]
    ) {
        updateSettings(coalescePersistence: true) { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
                return
            }

            let existing = settings.favoriteWatchedFolders[index]
            let scopedRelativePaths = ReaderFavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
                from: knownDocumentFileURLs,
                relativeTo: folderURL,
                options: existing.options
            )
            let updatedKnownPaths = Array(
                Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
            ).sorted()
            guard existing.allKnownRelativePaths != updatedKnownPaths else {
                return
            }

            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existing.id,
                name: existing.name,
                folderPath: existing.folderPath,
                options: existing.options,
                bookmarkData: existing.bookmarkData,
                openDocumentRelativePaths: existing.openDocumentRelativePaths,
                allKnownRelativePaths: updatedKnownPaths,
                workspaceState: existing.workspaceState,
                createdAt: existing.createdAt
            )
        }
    }

    func resolvedFavoriteWatchedFolderURL(for entry: ReaderFavoriteWatchedFolder) -> URL {
        guard let bookmarkData = entry.bookmarkData else {
            return entry.folderURL
        }

        do {
            let resolution = try bookmarkResolver(bookmarkData)

            if resolution.isStale {
                refreshFavoriteWatchedFolderBookmark(for: entry, resolvedURL: resolution.url)
            }

            return resolution.url
        } catch {
            updateFavoriteWatchedFolderBookmarkData(id: entry.id, bookmarkData: nil)
            return entry.folderURL
        }
    }

    func reorderFavoriteWatchedFolders(orderedIDs: [UUID]) {
        updateSettings { settings in
            settings.favoriteWatchedFolders = ReaderFavoriteHistory.reordering(
                ids: orderedIDs,
                in: settings.favoriteWatchedFolders
            )
        }
    }

    func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
        updateSettings(coalescePersistence: true) { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
                return
            }
            let existing = settings.favoriteWatchedFolders[index]
            guard existing.workspaceState != workspaceState else {
                return
            }
            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existing.id,
                name: existing.name,
                folderPath: existing.folderPath,
                options: existing.options,
                bookmarkData: existing.bookmarkData,
                openDocumentRelativePaths: existing.openDocumentRelativePaths,
                allKnownRelativePaths: existing.allKnownRelativePaths,
                workspaceState: workspaceState,
                createdAt: existing.createdAt
            )
        }
    }

    func clearFavoriteWatchedFolders() {
        updateSettings { settings in
            settings.favoriteWatchedFolders = []
        }
    }

    func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String]) {
        updateSettings { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
                return
            }

            let existing = settings.favoriteWatchedFolders[index]
            let updatedOptions = ReaderFolderWatchOptions(
                openMode: existing.options.openMode,
                scope: existing.options.scope,
                excludedSubdirectoryPaths: excludedSubdirectoryPaths
            )

            guard existing.options != updatedOptions else {
                return
            }

            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existing.id,
                name: existing.name,
                folderPath: existing.folderPath,
                options: updatedOptions,
                bookmarkData: existing.bookmarkData,
                openDocumentRelativePaths: existing.openDocumentRelativePaths,
                allKnownRelativePaths: existing.allKnownRelativePaths,
                workspaceState: existing.workspaceState,
                createdAt: existing.createdAt
            )
        }
    }

    private func refreshFavoriteWatchedFolderBookmark(for entry: ReaderFavoriteWatchedFolder, resolvedURL: URL) {
        let refreshedBookmarkData = try? bookmarkCreator(resolvedURL)
        let normalizedResolvedPath = ReaderFileRouting.normalizedFileURL(resolvedURL).path

        updateSettings { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == entry.id }) else {
                return
            }

            let existing = settings.favoriteWatchedFolders[index]
            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existing.id,
                name: existing.name,
                folderPath: normalizedResolvedPath,
                options: existing.options,
                bookmarkData: refreshedBookmarkData ?? existing.bookmarkData,
                openDocumentRelativePaths: existing.openDocumentRelativePaths,
                allKnownRelativePaths: existing.allKnownRelativePaths,
                workspaceState: existing.workspaceState,
                createdAt: existing.createdAt
            )
        }
    }

    private func updateFavoriteWatchedFolderBookmarkData(id: UUID, bookmarkData: Data?) {
        updateSettings { settings in
            guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
                return
            }

            let existingEntry = settings.favoriteWatchedFolders[index]
            guard existingEntry.bookmarkData != bookmarkData else {
                return
            }

            settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
                id: existingEntry.id,
                name: existingEntry.name,
                folderPath: existingEntry.folderPath,
                options: existingEntry.options,
                bookmarkData: bookmarkData,
                openDocumentRelativePaths: existingEntry.openDocumentRelativePaths,
                allKnownRelativePaths: existingEntry.allKnownRelativePaths,
                workspaceState: existingEntry.workspaceState,
                createdAt: existingEntry.createdAt
            )
        }
    }
}
