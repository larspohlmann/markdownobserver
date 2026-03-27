import Foundation

extension ReaderSettingsStore {
    func addFavoriteWatchedFolder(name: String, folderURL: URL, options: ReaderFolderWatchOptions) {
        updateSettings { settings in
            settings.favoriteWatchedFolders = ReaderFavoriteHistory.insertingUniqueFavorite(
                name: name,
                folderURL: folderURL,
                options: options,
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

    func clearFavoriteWatchedFolders() {
        updateSettings { settings in
            settings.favoriteWatchedFolders = []
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
                createdAt: existingEntry.createdAt
            )
        }
    }
}
