//
//  MarkdownLinkResolver.swift
//  minimark
//

import Foundation

/// Resolves a `file://` URL produced by WKWebView's navigation delegate into a
/// concrete on-disk markdown file URL, given the currently-open document's
/// directory and the bundle base URL that WKWebView uses to resolve relative
/// hrefs in the rendered preview.
///
/// The rendered HTML is loaded with `baseURL: Bundle.main.bundleURL`, so a
/// markdown link like `[x](other.md)` arrives at the navigation delegate as
/// `file:///Applications/MarkdownObserver.app/other.md`. This type detects that
/// case by prefix-matching against the bundle path, strips the bundle prefix,
/// and re-resolves the remainder against the current document's directory.
enum MarkdownLinkResolver {
    /// Returns the resolved markdown file URL, or `nil` if the input is not a
    /// markdown link we should follow (wrong scheme, wrong extension, missing
    /// document context).
    ///
    /// - Parameters:
    ///   - url: The URL from the `WKNavigationAction.request`.
    ///   - documentDirectoryPath: The directory containing the currently-open
    ///     document. `nil` means we have no document context yet, in which
    ///     case relative-style links cannot be resolved.
    ///   - bundlePath: The standardized path of the app bundle URL — used to
    ///     detect bundle-prefixed file URLs that originated as relative hrefs.
    static func resolveMarkdownLink(
        url: URL,
        documentDirectoryPath: String?,
        bundlePath: String
    ) -> URL? {
        guard url.isFileURL else { return nil }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        guard let bareURL = components?.url else { return nil }

        let candidatePath = bareURL.standardizedFileURL.path

        let resolvedPath: String
        if candidatePath == bundlePath || candidatePath.hasPrefix(bundlePath + "/") {
            // Was a relative href before WKWebView resolved it against the
            // bundle baseURL — strip the bundle prefix, re-resolve against
            // the document directory.
            guard let documentDirectoryPath else { return nil }
            let relative = String(candidatePath.dropFirst(bundlePath.count).drop(while: { $0 == "/" }))
            guard !relative.isEmpty else { return nil }
            resolvedPath = URL(fileURLWithPath: documentDirectoryPath)
                .appendingPathComponent(relative)
                .standardizedFileURL
                .path
        } else {
            resolvedPath = candidatePath
        }

        let resolvedURL = URL(fileURLWithPath: resolvedPath)
        guard isMarkdownExtension(resolvedURL.pathExtension) else { return nil }
        return resolvedURL
    }

    private static func isMarkdownExtension(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "md" || lower == "markdown"
    }
}
