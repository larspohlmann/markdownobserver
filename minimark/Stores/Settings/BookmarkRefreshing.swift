import Foundation

@MainActor
struct BookmarkRefreshing {
    typealias Resolver = (Data) throws -> (url: URL, isStale: Bool)
    typealias Creator = (URL) throws -> Data

    let resolve: Resolver
    let create: Creator

    init(resolve: @escaping Resolver, create: @escaping Creator) {
        self.resolve = resolve
        self.create = create
    }

    /// Resolves `bookmarkData` to a URL.
    ///
    /// - If `bookmarkData` is `nil`, returns `fallbackURL` without invoking callbacks.
    /// - If resolution succeeds and the bookmark is fresh, returns the resolved URL.
    /// - If resolution succeeds but the bookmark is stale, creates a refreshed bookmark
    ///   (swallowing creation errors), invokes `onStale(resolvedURL, refreshedData)`, and
    ///   returns the resolved URL. `refreshedData` is `nil` when creation fails.
    /// - If resolution throws, invokes `onFailure()` and returns `fallbackURL`.
    func resolveURL(
        bookmarkData: Data?,
        fallbackURL: URL,
        onStale: (URL, Data?) -> Void,
        onFailure: () -> Void
    ) -> URL {
        guard let bookmarkData else {
            return fallbackURL
        }

        do {
            let resolution = try resolve(bookmarkData)

            if resolution.isStale {
                let refreshedBookmarkData = try? create(resolution.url)
                onStale(resolution.url, refreshedBookmarkData)
            }

            return resolution.url
        } catch {
            onFailure()
            return fallbackURL
        }
    }
}
