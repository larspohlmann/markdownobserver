import Foundation

struct ReaderCSSFactory {
    static var screenshotAutoExpandMetaTag: String {
        let shouldExpand = ProcessInfo.processInfo.environment[
            ReaderUITestLaunchConfiguration.screenshotExpandFirstEditEnvironmentKey
        ] == "true"
        return shouldExpand
            ? "<meta name=\"minimark-auto-expand-first-edit\" content=\"true\" />"
            : ""
    }

    func makeCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: syntaxTheme, baseFontSize: baseFontSize)
    }

    func makeHTMLDocument(
        css: String,
        payloadBase64: String,
        runtimeAssets: ReaderRuntimeAssets,
        themeJavaScript: String? = nil
    ) -> String {
        let cssBase64 = Data(css.utf8).base64EncodedString()
        let themeJSBase64 = themeJavaScript.map { Data($0.utf8).base64EncodedString() }
        let runtimeScripts = makeRuntimeScripts(runtimeAssets: runtimeAssets)
        let mathRuntimeScripts = makeMathRuntimeScripts()
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
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' file:; style-src 'unsafe-inline' file:; img-src data: https:; frame-ancestors 'none'\" />
          <meta name="minimark-runtime-payload-base64" content="\(payloadBase64)" />
          <meta name="minimark-runtime-css-base64" content="\(cssBase64)" />
          \(themeJSBase64.map { "<meta name=\"minimark-runtime-theme-js-base64\" content=\"\($0)\" />" } ?? "")
          \(Self.screenshotAutoExpandMetaTag)
          <style id="minimark-runtime-style">
          \(css)
          </style>
          \(runtimeScripts)
          \(mathRuntimeScripts)
        </head>
        <body>
            <div class="reader-layout">
              <main id="reader-root" class="markdown-body" role="document"></main>
              <div id="reader-change-gutter" class="reader-change-gutter" role="navigation" aria-label="Changed regions"></div>
            </div>
          \(bootstrapRuntime)
          \(themeJSBase64 != nil ? ReaderJavaScriptLoader.themeJSBootstrapScript : "")
        </body>
        </html>
        """
    }

    private func makeRuntimeScripts(runtimeAssets: ReaderRuntimeAssets) -> String {
      var orderedScriptPaths: [String] = [runtimeAssets.markdownItScriptPath]
      orderedScriptPaths.append(contentsOf: [
        runtimeAssets.taskListsScriptPath,
        runtimeAssets.footnoteScriptPath,
        runtimeAssets.attrsScriptPath,
        runtimeAssets.deflistScriptPath
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

    private func makeMathRuntimeScripts() -> String {
      """
      <script>
      // MathJax is optional. Avoid remote script injection to keep rendering local-only.
      // If a local MathJax bundle is added later, this config remains compatible.
      if (!window.MathJax) {
        window.MathJax = {
          tex: {
            inlineMath: [["$", "$"], ["\\\\(", "\\\\)"]],
            displayMath: [["$$", "$$"], ["\\\\[", "\\\\]"]],
            processEscapes: true
          },
          options: {
            skipHtmlTags: ["script", "noscript", "style", "textarea", "pre", "code"]
          }
        };
      }
      </script>
      """
    }

    private func makeBootstrapRuntime(payloadBase64: String, cssBase64: String) -> String {
        let escapedPayload = payloadBase64.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedCSS = cssBase64.replacingOccurrences(of: "\"", with: "\\\"")

        let inlineDiffJS = ReaderJavaScriptLoader.loadBundledJS(named: "markdownobserver-inline-diff")
        let defaultInset = "\(Int(ReaderOverlayInsetCalculator.defaultScrollTargetTopInset.rounded()))"
        let runtimeJS = ReaderJavaScriptLoader.loadBundledJS(named: "markdownobserver-runtime")
            .replacingOccurrences(of: "__MINIMARK_PAYLOAD_BASE64__", with: escapedPayload)
            .replacingOccurrences(of: "__MINIMARK_CSS_BASE64__", with: escapedCSS)
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
}
