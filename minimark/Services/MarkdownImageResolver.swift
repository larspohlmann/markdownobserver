import Foundation
import UniformTypeIdentifiers

/// Resolves local image references in markdown text to inline data URIs.
/// This allows WKWebView to display images that reference local files,
/// bypassing WebKit's sandboxed process file access restrictions.
enum MarkdownImageResolver {

    /// Maximum image file size to inline (2 MB). Larger images are left as-is
    /// to avoid bloating the HTML string and memory usage.
    private static let maxImageSize = 2_000_000

    /// Cache of resolved data URIs keyed by absolute file path + modification date.
    /// Prevents repeated disk reads and base64 encoding across re-renders.
    private static var cache = [String: String]()

    /// Resolves relative and file:// image references to data URIs.
    /// - Parameters:
    ///   - markdown: The raw markdown text.
    ///   - documentDirectoryURL: The directory containing the markdown file.
    /// - Returns: Markdown with local image references replaced by data URIs.
    static func resolve(markdown: String, documentDirectoryURL: URL?) -> String {
        guard let documentDirectoryURL else { return markdown }

        // Match ![alt](url) and ![alt](url "title"), skipping content
        // inside fenced code blocks (``` ... ```) and inline code (` ... `).
        let pattern = #"(?:^|\n)(`{3,})[^\n]*\n[\s\S]*?\n\1|`[^`\n]+`|!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return markdown
        }

        var result = markdown
        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

        // Process matches in reverse order so replacements don't shift indices.
        for match in matches.reversed() {
            // Groups 2 and 3 are only set for image matches (not code blocks/spans).
            guard match.range(at: 2).location != NSNotFound,
                  match.range(at: 3).location != NSNotFound,
                  let urlRange = Range(match.range(at: 3), in: markdown) else {
                continue
            }

            let urlString = String(markdown[urlRange]).trimmingCharacters(in: .whitespaces)

            guard let dataURI = dataURI(for: urlString, relativeTo: documentDirectoryURL) else {
                continue
            }

            let fullRange = Range(match.range, in: result)!
            let altRange = Range(match.range(at: 2), in: markdown)!
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
            // Relative path — strip <...> angle bracket wrappers if present
            var cleaned = urlString
            if cleaned.hasPrefix("<") && cleaned.hasSuffix(">") {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            fileURL = baseURL.appendingPathComponent(cleaned).standardized
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let mimeType = imageMIMEType(for: fileURL) else {
            return nil // Not an image file
        }

        // Check cache by path + modification date.
        let cacheKey = cacheKey(for: fileURL)
        if let cached = cache[cacheKey] {
            return cached
        }

        // Skip files that are too large to inline.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? Int,
              fileSize <= maxImageSize else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let base64 = data.base64EncodedString()
        let result = "data:\(mimeType);base64,\(base64)"
        cache[cacheKey] = result
        return result
    }

    private static func cacheKey(for url: URL) -> String {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return "\(url.path)|\(mtime?.timeIntervalSince1970 ?? 0)"
    }

    private static func imageMIMEType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else { return nil }
        guard utType.conforms(to: .image) else { return nil }
        return utType.preferredMIMEType
    }
}
