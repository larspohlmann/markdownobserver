import Foundation

extension ReaderSettingsStore {
    func addRecentWatchedFolder(_ folderURL: URL, options: ReaderFolderWatchOptions) {
        updateSettings { settings in
            settings.recentWatchedFolders = ReaderRecentHistory.insertingUniqueWatchedFolder(
                folderURL,
                options: options,
                into: settings.recentWatchedFolders
            )
        }
    }

    func resolvedRecentWatchedFolderURL(matching folderURL: URL) -> URL? {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard let entry = currentSettings.recentWatchedFolders.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.folderURL) == normalizedFolderURL
        }) else {
            return nil
        }

        return resolveRecentWatchedFolderURL(for: entry)
    }

    func clearRecentWatchedFolders() {
        updateSettings { settings in
            settings.recentWatchedFolders = []
        }
    }

    func addRecentManuallyOpenedFile(_ fileURL: URL) {
        updateSettings { settings in
            settings.recentManuallyOpenedFiles = ReaderRecentHistory.insertingUniqueFile(
                fileURL,
                into: settings.recentManuallyOpenedFiles
            )
        }
    }

    func resolvedRecentManuallyOpenedFileURL(matching fileURL: URL) -> URL? {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        guard let entry = currentSettings.recentManuallyOpenedFiles.first(where: { entry in
            ReaderFileRouting.normalizedFileURL(entry.fileURL) == normalizedFileURL
        }) else {
            return nil
        }

        return resolveRecentOpenedFileURL(for: entry)
    }

    func clearRecentManuallyOpenedFiles() {
        updateSettings { settings in
            settings.recentManuallyOpenedFiles = []
        }
    }

    private func resolveRecentOpenedFileURL(for entry: ReaderRecentOpenedFile) -> URL {
        guard let bookmarkData = entry.bookmarkData else {
            return entry.fileURL
        }

        do {
            let resolution = try bookmarkResolver(bookmarkData)

            if resolution.isStale {
                refreshRecentOpenedFileBookmark(for: entry, resolvedURL: resolution.url)
            }

            return resolution.url
        } catch {
            updateRecentOpenedFileBookmarkData(forPath: entry.filePath, bookmarkData: nil)
            return entry.fileURL
        }
    }

    private func resolveRecentWatchedFolderURL(for entry: ReaderRecentWatchedFolder) -> URL {
        guard let bookmarkData = entry.bookmarkData else {
            return entry.folderURL
        }

        do {
            let resolution = try bookmarkResolver(bookmarkData)

            if resolution.isStale {
                refreshRecentWatchedFolderBookmark(for: entry, resolvedURL: resolution.url)
            }

            return resolution.url
        } catch {
            updateRecentWatchedFolderBookmarkData(forPath: entry.folderPath, bookmarkData: nil)
            return entry.folderURL
        }
    }

    private func refreshRecentOpenedFileBookmark(for entry: ReaderRecentOpenedFile, resolvedURL: URL) {
        let refreshedBookmarkData = try? bookmarkCreator(resolvedURL)
        updateRecentOpenedFileBookmarkData(forPath: entry.filePath, bookmarkData: refreshedBookmarkData)
    }

    private func refreshRecentWatchedFolderBookmark(for entry: ReaderRecentWatchedFolder, resolvedURL: URL) {
        let refreshedBookmarkData = try? bookmarkCreator(resolvedURL)
        updateRecentWatchedFolderBookmarkData(forPath: entry.folderPath, bookmarkData: refreshedBookmarkData)
    }

    private func updateRecentOpenedFileBookmarkData(forPath filePath: String, bookmarkData: Data?) {
        updateSettings { settings in
            guard let index = settings.recentManuallyOpenedFiles.firstIndex(where: { $0.filePath == filePath }) else {
                return
            }

            let existingEntry = settings.recentManuallyOpenedFiles[index]
            guard existingEntry.bookmarkData != bookmarkData else {
                return
            }

            settings.recentManuallyOpenedFiles[index] = ReaderRecentOpenedFile(
                filePath: existingEntry.filePath,
                bookmarkData: bookmarkData
            )
        }
    }

    private func updateRecentWatchedFolderBookmarkData(forPath folderPath: String, bookmarkData: Data?) {
        updateSettings { settings in
            guard let index = settings.recentWatchedFolders.firstIndex(where: { $0.folderPath == folderPath }) else {
                return
            }

            let existingEntry = settings.recentWatchedFolders[index]
            guard existingEntry.bookmarkData != bookmarkData else {
                return
            }

            settings.recentWatchedFolders[index] = ReaderRecentWatchedFolder(
                folderPath: existingEntry.folderPath,
                options: existingEntry.options,
                bookmarkData: bookmarkData
            )
        }
    }
}
