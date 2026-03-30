import Foundation

nonisolated enum ReaderFileRouting {
    private nonisolated static let supportedMarkdownExtensions: Set<String> = ["md", "markdown", "mdown"]

    nonisolated static func supportedMarkdownFiles(from urls: [URL]) -> [URL] {
        urls
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { supportedMarkdownExtensions.contains($0.pathExtension.lowercased()) }
    }

    nonisolated static func normalizedFileURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    nonisolated static func isSupportedMarkdownFileURL(_ url: URL) -> Bool {
        supportedMarkdownExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func firstDroppedDirectoryURL(from urls: [URL]) -> URL? {
        urls
            .lazy
            .map(normalizedFileURL)
            .first(where: isDirectoryURL)
    }
    
    nonisolated static func plannedOpenFileURLs(from urls: [URL]) -> [URL] {
        Array(Set(urls.map(normalizedFileURL)))
            .sorted { $0.path < $1.path }
    }

    private nonisolated static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
