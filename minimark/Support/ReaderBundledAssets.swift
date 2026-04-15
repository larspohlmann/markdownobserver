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
    // Resolved relative to Bundle.main.bundleURL used by WKWebView loadHTMLString.
    static let markdownItScriptPath = "Contents/Resources/markdown-it.min.js"
    static let highlightJSScriptPath = "Contents/Resources/highlight.min.js"
    static let codeMirrorSourceViewScriptPath = "Contents/Resources/codemirror-source-view.js"
    static let taskListsScriptPath = "Contents/Resources/markdown-it-task-lists.min.js"
    static let footnoteScriptPath = "Contents/Resources/markdown-it-footnote.min.js"
    static let attrsScriptPath = "Contents/Resources/markdown-it-attrs.min.js"
    static let deflistScriptPath = "Contents/Resources/markdown-it-deflist.min.js"
    static let mermaidScriptPath = "Contents/Resources/mermaid.min.js"
    static let mermaidCSSPath = "Contents/Resources/mermaid-diagrams.css"

    static func requiredRuntimeAssets() throws -> ReaderRuntimeAssets {
        let markdownURL = Bundle.main.bundleURL.appendingPathComponent(markdownItScriptPath)
        guard FileManager.default.fileExists(atPath: markdownURL.path) else {
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

    private static func availableScriptPath(_ path: String) -> String? {
        let fileURL = Bundle.main.bundleURL.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: fileURL.path) ? path : nil
    }
}
