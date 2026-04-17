import Foundation
import Combine
import Observation

@MainActor @Observable final class FavoriteWatchedFoldersStore: ReaderFavoriteWriting {
    private(set) var currentFavorites: [ReaderFavoriteWatchedFolder]

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<[ReaderFavoriteWatchedFolder], Never>

    @ObservationIgnored
    private let bookmarkRefreshing: BookmarkRefreshing

    var favoritesPublisher: AnyPublisher<[ReaderFavoriteWatchedFolder], Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: [ReaderFavoriteWatchedFolder], bookmarkRefreshing: BookmarkRefreshing) {
        self.currentFavorites = initial
        self.subject = CurrentValueSubject(initial)
        self.bookmarkRefreshing = bookmarkRefreshing
    }

    func addFavoriteWatchedFolder(
        name: String,
        folderURL: URL,
        options: FolderWatchOptions,
        openDocumentFileURLs: [URL] = [],
        workspaceState: ReaderFavoriteWorkspaceState = .from(
            settings: .default,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )
    ) {
        mutate(coalescePersistence: false) { favorites in
            favorites = ReaderFavoriteHistory.insertingUniqueFavorite(
                name: name,
                folderURL: folderURL,
                options: options,
                openDocumentFileURLs: openDocumentFileURLs,
                workspaceState: workspaceState,
                into: favorites
            )
        }
    }

    func removeFavoriteWatchedFolder(id: UUID) {
        mutate(coalescePersistence: false) { favorites in
            favorites = ReaderFavoriteHistory.removingFavorite(id: id, from: favorites)
        }
    }

    func renameFavoriteWatchedFolder(id: UUID, newName: String) {
        mutate(coalescePersistence: false) { favorites in
            favorites = ReaderFavoriteHistory.renamingFavorite(id: id, newName: newName, in: favorites)
        }
    }

    func updateFavoriteWatchedFolderOpenDocuments(
        id: UUID,
        folderURL: URL,
        openDocumentFileURLs: [URL]
    ) {
        mutate(coalescePersistence: true) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }

            let existing = favorites[index]
            let scopedRelativePaths = ReaderFavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
                from: openDocumentFileURLs,
                relativeTo: folderURL,
                options: existing.options
            )
            guard existing.openDocumentRelativePaths != scopedRelativePaths else { return }

            let updatedKnownPaths = Array(
                Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
            ).sorted()

            favorites[index] = Self.copy(
                existing,
                openDocumentRelativePaths: scopedRelativePaths,
                allKnownRelativePaths: updatedKnownPaths
            )
        }
    }

    func updateFavoriteWatchedFolderKnownDocuments(
        id: UUID,
        folderURL: URL,
        knownDocumentFileURLs: [URL]
    ) {
        mutate(coalescePersistence: true) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }

            let existing = favorites[index]
            let scopedRelativePaths = ReaderFavoriteWatchedFolder.scopedOpenDocumentRelativePaths(
                from: knownDocumentFileURLs,
                relativeTo: folderURL,
                options: existing.options
            )
            let updatedKnownPaths = Array(
                Set(existing.allKnownRelativePaths).union(scopedRelativePaths)
            ).sorted()
            guard existing.allKnownRelativePaths != updatedKnownPaths else { return }

            favorites[index] = Self.copy(existing, allKnownRelativePaths: updatedKnownPaths)
        }
    }

    func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
        mutate(coalescePersistence: true) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
            let existing = favorites[index]
            guard existing.workspaceState != workspaceState else { return }
            favorites[index] = Self.copy(existing, workspaceState: workspaceState)
        }
    }

    func resolvedFavoriteWatchedFolderURL(for entry: ReaderFavoriteWatchedFolder) -> URL {
        bookmarkRefreshing.resolveURL(
            bookmarkData: entry.bookmarkData,
            fallbackURL: entry.folderURL,
            onStale: { [weak self] resolvedURL, refreshedBookmarkData in
                self?.replaceEntryForStaleBookmark(
                    id: entry.id,
                    resolvedURL: resolvedURL,
                    refreshedBookmarkData: refreshedBookmarkData
                )
            },
            onFailure: { [weak self] in
                self?.updateFavoriteWatchedFolderBookmarkData(id: entry.id, bookmarkData: nil)
            }
        )
    }

    func clearFavoriteWatchedFolders() {
        mutate(coalescePersistence: false) { favorites in
            favorites = []
        }
    }

    func reorderFavoriteWatchedFolders(orderedIDs: [UUID]) {
        mutate(coalescePersistence: false) { favorites in
            favorites = ReaderFavoriteHistory.reordering(ids: orderedIDs, in: favorites)
        }
    }

    func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String]) {
        mutate(coalescePersistence: false) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }

            let existing = favorites[index]
            let folderURL = URL(fileURLWithPath: existing.folderPath, isDirectory: true)
            let normalizedOptions = FolderWatchOptions(
                openMode: existing.options.openMode,
                scope: existing.options.scope,
                excludedSubdirectoryPaths: excludedSubdirectoryPaths
            ).encodedForFolder(folderURL)

            guard existing.options != normalizedOptions else { return }

            favorites[index] = Self.copy(existing, options: normalizedOptions)
        }
    }

    private func replaceEntryForStaleBookmark(
        id: UUID,
        resolvedURL: URL,
        refreshedBookmarkData: Data?
    ) {
        let normalizedResolvedPath = ReaderFileRouting.normalizedFileURL(resolvedURL).path

        mutate(coalescePersistence: false) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }
            let existing = favorites[index]
            favorites[index] = Self.copy(
                existing,
                folderPath: normalizedResolvedPath,
                bookmarkData: refreshedBookmarkData ?? existing.bookmarkData
            )
        }
    }

    private func updateFavoriteWatchedFolderBookmarkData(id: UUID, bookmarkData: Data?) {
        mutate(coalescePersistence: false) { favorites in
            guard let index = favorites.firstIndex(where: { $0.id == id }) else { return }

            let existing = favorites[index]
            guard existing.bookmarkData != bookmarkData else { return }

            favorites[index] = Self.copy(existing, bookmarkData: bookmarkData)
        }
    }

    private static func copy(
        _ entry: ReaderFavoriteWatchedFolder,
        folderPath: String? = nil,
        options: FolderWatchOptions? = nil,
        bookmarkData: Data?? = nil,
        openDocumentRelativePaths: [String]? = nil,
        allKnownRelativePaths: [String]? = nil,
        workspaceState: ReaderFavoriteWorkspaceState? = nil
    ) -> ReaderFavoriteWatchedFolder {
        ReaderFavoriteWatchedFolder(
            id: entry.id,
            name: entry.name,
            folderPath: folderPath ?? entry.folderPath,
            options: options ?? entry.options,
            bookmarkData: bookmarkData ?? entry.bookmarkData,
            openDocumentRelativePaths: openDocumentRelativePaths ?? entry.openDocumentRelativePaths,
            allKnownRelativePaths: allKnownRelativePaths ?? entry.allKnownRelativePaths,
            workspaceState: workspaceState ?? entry.workspaceState,
            createdAt: entry.createdAt
        )
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout [ReaderFavoriteWatchedFolder]) -> Void
    ) {
        var updated = currentFavorites
        transform(&updated)
        guard updated != currentFavorites else { return }
        currentFavorites = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
