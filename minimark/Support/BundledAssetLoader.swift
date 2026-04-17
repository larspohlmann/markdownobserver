import Foundation
import os

enum BundledAssetLoader {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "minimark",
        category: "BundledAssetLoader"
    )

    private static var bundledJSCache: [String: String] = [:]
    private static var bundledCSSCache: [String: String] = [:]

    static func loadBundledJS(named name: String) -> String {
        if let cached = bundledJSCache[name] {
            return cached
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Failed to load bundled JS resource: \(name, privacy: .public).js")
            #if DEBUG
            assertionFailure("Failed to load bundled JS resource named '\(name).js' from main bundle.")
            #endif
            let fallback = "console.error('Failed to load bundled JS resource: \(name).js');"
            bundledJSCache[name] = fallback
            return fallback
        }

        bundledJSCache[name] = contents
        return contents
    }

    static func loadBundledCSS(named name: String) -> String {
        if let cached = bundledCSSCache[name] {
            return cached
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "css"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Failed to load bundled CSS resource: \(name, privacy: .public).css")
            #if DEBUG
            assertionFailure("Failed to load bundled CSS resource named '\(name).css' from main bundle.")
            #endif
            let fallback = "/* Failed to load bundled CSS resource: \(name).css */"
            bundledCSSCache[name] = fallback
            return fallback
        }

        bundledCSSCache[name] = contents
        return contents
    }

    static var inlineDiffRuntimeJavaScript: String {
        loadBundledJS(named: "markdownobserver-inline-diff")
    }

    static var scrollSyncObserverJavaScript: String {
        loadBundledJS(named: "markdownobserver-scroll-sync")
    }

    static var themeJSBootstrapScript: String {
        "<script>\n\(loadBundledJS(named: "theme-bootstrap"))\n</script>"
    }
}
