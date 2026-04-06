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
        if let hintedDirectoryURL = urls.first(where: \.hasDirectoryPath) {
            return normalizedFileURL(hintedDirectoryURL)
        }

        return urls
            .lazy
            .map(normalizedFileURL)
            .first(where: isDirectoryURL)
    }

    nonisolated static func containsLikelyDirectoryPath(in urls: [URL]) -> Bool {
        urls.contains(where: \.hasDirectoryPath)
    }

    private nonisolated static func isDirectoryURL(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
