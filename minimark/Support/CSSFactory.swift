import Foundation

struct CSSFactory {
    static var screenshotAutoExpandMetaTag: String {
        let shouldExpand = ProcessInfo.processInfo.environment[
            UITestLaunchConfiguration.screenshotExpandFirstEditEnvironmentKey
        ] == "true"
        return shouldExpand
            ? "<meta name=\"minimark-auto-expand-first-edit\" content=\"true\" />"
            : ""
    }

    func makeCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        CSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: syntaxTheme, baseFontSize: baseFontSize)
    }

    func makeHTMLDocument(
        css: String,
        payloadBase64: String,
        runtimeAssets: RuntimeAssets,
        themeJavaScript: String? = nil
    ) -> String {
        let cssBase64 = Data(css.utf8).base64EncodedString()
        let themeJSBase64 = themeJavaScript.map { Data($0.utf8).base64EncodedString() }
        let runtimeScripts = makeRuntimeScripts(runtimeAssets: runtimeAssets)
        let runtimeCSSLinks = makeRuntimeCSSLinks(runtimeAssets: runtimeAssets)
        let bootstrapRuntime = makeBootstrapRuntime(
            payloadBase64: payloadBase64,
            cssBase64: cssBase64
        )
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' file:; style-src 'unsafe-inline' file:; img-src data: https:; font-src file:; frame-ancestors 'none'\" />
          <meta name="minimark-runtime-payload-base64" content="\(payloadBase64)" />
          <meta name="minimark-runtime-css-base64" content="\(cssBase64)" />
          \(themeJSBase64.map { "<meta name=\"minimark-runtime-theme-js-base64\" content=\"\($0)\" />" } ?? "")
          \(Self.screenshotAutoExpandMetaTag)
          <style id="minimark-runtime-style">
          \(css)
          </style>
          \(runtimeScripts)
          \(runtimeCSSLinks)
        </head>
        <body>
            <div class="reader-layout">
              <main id="reader-root" class="markdown-body" role="document"></main>
              <div id="reader-change-gutter" class="reader-change-gutter" role="navigation" aria-label="Changed regions"></div>
            </div>
          \(bootstrapRuntime)
          \(themeJSBase64 != nil ? BundledAssetLoader.themeJSBootstrapScript : "")
        </body>
        </html>
        """
    }

    private func makeRuntimeScripts(runtimeAssets: RuntimeAssets) -> String {
      var orderedScriptPaths: [String] = [runtimeAssets.markdownItScriptPath]
      orderedScriptPaths.append(contentsOf: [
        runtimeAssets.taskListsScriptPath,
        runtimeAssets.footnoteScriptPath,
        runtimeAssets.attrsScriptPath,
        runtimeAssets.deflistScriptPath,
        runtimeAssets.calloutsScriptPath
      ].compactMap { $0 })

      if let highlightScriptPath = runtimeAssets.highlightScriptPath {
        orderedScriptPaths.append(highlightScriptPath)
      }

      return orderedScriptPaths
        .map(makeScriptTag)
        .joined(separator: "\n")
    }

    private func makeScriptTag(for path: String) -> String {
      let escapedPath = path.replacingOccurrences(of: "\"", with: "&quot;")
      return "<script src=\"\(escapedPath)\"></script>"
    }

    private func makeCSSLinkTag(for path: String) -> String {
      let escapedPath = path.replacingOccurrences(of: "\"", with: "&quot;")
      return "<link rel=\"stylesheet\" href=\"\(escapedPath)\" />"
    }

    private func makeRuntimeCSSLinks(runtimeAssets: RuntimeAssets) -> String {
      [runtimeAssets.calloutsCSSPath].compactMap { $0 }.map(makeCSSLinkTag).joined(separator: "\n")
    }

    private func makeBootstrapRuntime(payloadBase64: String, cssBase64: String) -> String {
        let escapedPayload = payloadBase64.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedCSS = cssBase64.replacingOccurrences(of: "\"", with: "\\\"")

        let inlineDiffJS = BundledAssetLoader.loadBundledJS(named: "markdownobserver-inline-diff")
        let defaultInset = "\(Int(OverlayInsetCalculator.defaultScrollTargetTopInset.rounded()))"
        let runtimeJS = BundledAssetLoader.loadBundledJS(named: "markdownobserver-runtime")
            .replacingOccurrences(of: "__MINIMARK_PAYLOAD_BASE64__", with: escapedPayload)
            .replacingOccurrences(of: "__MINIMARK_CSS_BASE64__", with: escapedCSS)
            .replacingOccurrences(of: "__MINIMARK_LAZY_ASSET_PATHS_BASE64__", with: Self.lazyAssetPathsBase64)
            .replacingOccurrences(of: "__MINIMARK_OVERLAY_TOP_INSET__", with: defaultInset)

        return """
        <script>
        \(inlineDiffJS)
        </script>
        <script>
        \(runtimeJS)
        </script>
        """
    }

    // Encoded once at init — inputs are compile-time `BundledAssets` constants
    // and stable key order keeps the output byte-stable so the HTML-equality
    // fast-path in MarkdownWebView isn't defeated by dictionary-order churn.
    // Encoding a struct of `String` fields is infallible today; if that ever
    // changes we surface the failure loudly in debug and log in release
    // rather than silently disabling lazy-loaded assets.
    private static let lazyAssetPathsBase64: String = {
        do {
            return try JSONBase64.encodeStable(BundledAssets.lazyAssetPaths)
        } catch {
            assertionFailure("Failed to encode lazy asset paths as base64: \(error)")
            NSLog("CSSFactory: failed to encode lazy asset paths as base64: %@", String(describing: error))
            return ""
        }
    }()
}
