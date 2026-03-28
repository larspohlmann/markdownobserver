import Foundation
import UniformTypeIdentifiers

/// Resolves local image references in markdown text to inline data URIs.
/// This allows WKWebView to display images that reference local files,
/// bypassing WebKit's sandboxed process file access restrictions.
enum MarkdownImageResolver {

    struct Result {
        let markdown: String
        /// True if some local images exist but couldn't be read (sandbox restriction).
        let needsDirectoryAccess: Bool
    }

    /// Maximum image file size to inline (2 MB). Larger images are left as-is
    /// to avoid bloating the HTML string and memory usage.
    private static let maxImageSize = 2_000_000

    /// Cache of resolved data URIs keyed by absolute file path + modification date.
    /// Prevents repeated disk reads and base64 encoding across re-renders.
    private static var cache = [String: String]()

    /// Resolves relative and file:// image references to data URIs.
    static func resolve(markdown: String, documentDirectoryURL: URL?) -> Result {
        guard let documentDirectoryURL else {
            return Result(markdown: markdown, needsDirectoryAccess: false)
        }

        // Match ![alt](url) and ![alt](url "title"), skipping content
        // inside fenced code blocks (``` ... ```) and inline code (` ... `).
        let pattern = #"(?:^|\n)(`{3,})[^\n]*\n[\s\S]*?\n\1|`[^`\n]+`|!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return Result(markdown: markdown, needsDirectoryAccess: false)
        }

        var result = markdown
        var hasUnreadableImages = false
        let matches = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))

        for match in matches.reversed() {
            guard match.range(at: 2).location != NSNotFound,
                  match.range(at: 3).location != NSNotFound,
                  let urlRange = Range(match.range(at: 3), in: markdown) else {
                continue
            }

            let urlString = String(markdown[urlRange]).trimmingCharacters(in: .whitespaces)

            switch resolveImage(for: urlString, relativeTo: documentDirectoryURL) {
            case .resolved(let dataURI):
                let fullRange = Range(match.range, in: result)!
                let altRange = Range(match.range(at: 2), in: markdown)!
                let altText = String(markdown[altRange])
                result.replaceSubrange(fullRange, with: "![\(altText)](\(dataURI))")
            case .unreadable:
                hasUnreadableImages = true
            case .skip:
                break
            }
        }

        return Result(markdown: result, needsDirectoryAccess: hasUnreadableImages)
    }

    // MARK: - Private

    private enum ImageResolution {
        case resolved(String)
        case unreadable
        case skip
    }

    private static func resolveImage(for urlString: String, relativeTo baseURL: URL) -> ImageResolution {
        let fileURL: URL

        if urlString.hasPrefix("#") {
            return .skip
        }

        let lowercased = urlString.lowercased()
        if lowercased.hasPrefix("file:///") {
            guard let url = URL(string: urlString) else { return .skip }
            fileURL = url
        } else if urlString.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: urlString)
        } else if hasURLScheme(urlString) {
            return .skip // data:, http(s):, mailto:, etc.
        } else {
            var cleaned = urlString
            if cleaned.hasPrefix("<") && cleaned.hasSuffix(">") {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            fileURL = baseURL.appendingPathComponent(cleaned).standardized
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .skip
        }

        guard let mimeType = imageMIMEType(for: fileURL) else {
            return .skip
        }

        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            return .unreadable
        }

        let cacheKey = cacheKey(for: fileURL)
        if let cached = cache[cacheKey] {
            return .resolved(cached)
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? Int,
              fileSize <= maxImageSize else {
            return .skip
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .unreadable
        }

        let base64 = data.base64EncodedString()
        let dataURI = "data:\(mimeType);base64,\(base64)"
        cache[cacheKey] = dataURI
        return .resolved(dataURI)
    }

    private static func cacheKey(for url: URL) -> String {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return "\(url.path)|\(mtime?.timeIntervalSince1970 ?? 0)"
    }

    private static func hasURLScheme(_ string: String) -> Bool {
        guard let colonIndex = string.firstIndex(of: ":"),
              let first = string.first, first.isLetter else {
            return false
        }
        let scheme = string[string.startIndex..<colonIndex]
        return scheme.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    private static func imageMIMEType(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard let utType = UTType(filenameExtension: ext) else { return nil }
        guard utType.conforms(to: .image) else { return nil }
        return utType.preferredMIMEType
    }
}
