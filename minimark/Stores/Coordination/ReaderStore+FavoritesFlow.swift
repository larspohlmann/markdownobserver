import Foundation

extension ReaderStore {
    var isCurrentWatchAFavorite: Bool {
        guard let session = activeFolderWatchSession else {
            return false
        }
        let normalizedPath = Self.normalizedFileURL(session.folderURL).path
        return settingsStore.currentSettings.favoriteWatchedFolders.contains {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }
    }

    func saveFolderWatchAsFavorite(name: String) {
        guard let session = activeFolderWatchSession else {
            return
        }

        settingsStore.addFavoriteWatchedFolder(
            name: name,
            folderURL: session.folderURL,
            options: session.options
        )
    }

    func removeCurrentWatchFromFavorites() {
        guard let session = activeFolderWatchSession else {
            return
        }

        let normalizedPath = Self.normalizedFileURL(session.folderURL).path
        guard let match = settingsStore.currentSettings.favoriteWatchedFolders.first(where: {
            $0.matches(folderPath: normalizedPath, options: session.options)
        }) else {
            return
        }

        settingsStore.removeFavoriteWatchedFolder(id: match.id)
    }

    func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
        let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry) ?? entry.folderURL
        startWatchingFolder(folderURL: resolvedURL, options: entry.options)
    }
}
