import Foundation

/// Resolves security-scoped bookmark data to a URL, falling back to an
/// original URL when bookmark data is absent or resolution fails.
///
/// Shared by `ReaderRecentOpenedFile` and `ReaderRecentWatchedFolder`.
enum BookmarkResolver {

    /// Resolve security-scoped bookmark data to a URL.
    ///
    /// Returns `fallbackURL` if `bookmarkData` is nil or resolution fails.
    nonisolated static func resolveSecurityScopedBookmark(
        _ bookmarkData: Data?,
        fallbackURL: URL
    ) -> URL {
        guard let bookmarkData else {
            return fallbackURL
        }

        var bookmarkIsStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &bookmarkIsStale
        ) else {
            return fallbackURL
        }

        return resolvedURL
    }
}
