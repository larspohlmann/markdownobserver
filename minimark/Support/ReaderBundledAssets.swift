import Foundation

struct ReaderRuntimeAssets: Equatable, Sendable {
    let markdownItScriptPath: String
    let highlightScriptPath: String?
    let taskListsScriptPath: String?
    let footnoteScriptPath: String?
    let attrsScriptPath: String?
    let deflistScriptPath: String?
}

protocol ReaderRuntimeAssetResolving {
    func requiredRuntimeAssets() throws -> ReaderRuntimeAssets
}

struct BundledReaderRuntimeAssetResolver: ReaderRuntimeAssetResolving {
    func requiredRuntimeAssets() throws -> ReaderRuntimeAssets {
        try ReaderBundledAssets.requiredRuntimeAssets()
    }
}

enum ReaderBundledAssets {
    // Absolute file:// URLs so scripts load regardless of the WKWebView baseURL.
    private static let bundleResourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")

    static let markdownItScriptPath = bundleResourcesURL.appendingPathComponent("markdown-it.min.js").absoluteString
    static let highlightJSScriptPath = bundleResourcesURL.appendingPathComponent("highlight.min.js").absoluteString
    static let codeMirrorSourceViewScriptPath = bundleResourcesURL.appendingPathComponent("codemirror-source-view.js").absoluteString
    static let taskListsScriptPath = bundleResourcesURL.appendingPathComponent("markdown-it-task-lists.min.js").absoluteString
    static let footnoteScriptPath = bundleResourcesURL.appendingPathComponent("markdown-it-footnote.min.js").absoluteString
    static let attrsScriptPath = bundleResourcesURL.appendingPathComponent("markdown-it-attrs.min.js").absoluteString
    static let deflistScriptPath = bundleResourcesURL.appendingPathComponent("markdown-it-deflist.min.js").absoluteString

    static func requiredRuntimeAssets() throws -> ReaderRuntimeAssets {
        guard let markdownURL = URL(string: markdownItScriptPath),
              FileManager.default.fileExists(atPath: markdownURL.path) else {
            throw ReaderError.markdownRuntimeUnavailable(markdownItScriptPath)
        }

        return ReaderRuntimeAssets(
            markdownItScriptPath: markdownItScriptPath,
            highlightScriptPath: availableHighlightJSScriptPath(),
            taskListsScriptPath: availableTaskListsScriptPath(),
            footnoteScriptPath: availableFootnoteScriptPath(),
            attrsScriptPath: availableAttrsScriptPath(),
            deflistScriptPath: availableDeflistScriptPath()
        )
    }

    static func availableHighlightJSScriptPath() -> String? {
        availableScriptPath(highlightJSScriptPath)
    }

    static func availableCodeMirrorSourceViewScriptPath() -> String? {
        availableScriptPath(codeMirrorSourceViewScriptPath)
    }

    static func availableTaskListsScriptPath() -> String? {
        availableScriptPath(taskListsScriptPath)
    }

    static func availableFootnoteScriptPath() -> String? {
        availableScriptPath(footnoteScriptPath)
    }

    static func availableAttrsScriptPath() -> String? {
        availableScriptPath(attrsScriptPath)
    }

    static func availableDeflistScriptPath() -> String? {
        availableScriptPath(deflistScriptPath)
    }

    private static func availableScriptPath(_ absoluteURLString: String) -> String? {
        guard let fileURL = URL(string: absoluteURLString),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return absoluteURLString
    }
}
