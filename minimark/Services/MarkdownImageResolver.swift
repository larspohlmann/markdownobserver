import Foundation
import UniformTypeIdentifiers

/// Resolves local image references in markdown text to inline data URIs.
/// This allows WKWebView to display images that reference local files,
/// bypassing WebKit's sandboxed process file access restrictions.
enum MarkdownImageResolver {

    /// Resolves relative and file:// image references to data URIs.
    /// - Parameters:
    ///   - markdown: The raw markdown text.
    ///   - documentDirectoryURL: The directory containing the markdown file.
    /// - Returns: Markdown with local image references replaced by data URIs.
    static func resolve(markdown: String, documentDirectoryURL: URL?) -> String {
        guard let documentDirectoryURL else { return markdown }

        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return markdown }

        var result = markdown
        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

        // Process matches in reverse order so replacements don't shift indices.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let urlRange = Range(match.range(at: 2), in: markdown) else {
                continue
            }

            let urlString = String(markdown[urlRange]).trimmingCharacters(in: .whitespaces)

            guard let dataURI = dataURI(for: urlString, relativeTo: documentDirectoryURL) else {
                continue
            }

            let fullRange = Range(match.range, in: result)!
            let altRange = Range(match.range(at: 1), in: markdown)!
            let altText = String(markdown[altRange])
            result.replaceSubrange(fullRange, with: "![\(altText)](\(dataURI))")
        }

        return result
    }

    private static func dataURI(for urlString: String, relativeTo baseURL: URL) -> String? {
        let fileURL: URL

        if urlString.lowercased().hasPrefix("data:") {
            return nil // Already a data URI
        } else if urlString.lowercased().hasPrefix("http://") || urlString.lowercased().hasPrefix("https://") {
            return nil // Remote URL — leave as-is
        } else if urlString.hasPrefix("#") {
            return nil // Fragment
        } else if urlString.lowercased().hasPrefix("file:///") {
            guard let url = URL(string: urlString) else { return nil }
            fileURL = url
        } else if urlString.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: urlString)
        } else {
            // Relative path
            fileURL = baseURL.appendingPathComponent(urlString).standardized
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let mimeType = imageMIMEType(for: fileURL) else {
            return nil // Not an image file
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let base64 = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }

    private static func imageMIMEType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else { return nil }
        guard utType.conforms(to: .image) else { return nil }
        return utType.preferredMIMEType
    }
}
