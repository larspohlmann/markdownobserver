import Foundation

enum ReaderJavaScriptLoader {
    private static var bundledJSCache: [String: String] = [:]

    static func loadBundledJS(named name: String) -> String {
        if let cached = bundledJSCache[name] {
            return cached
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
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

    static var inlineDiffRuntimeJavaScript: String {
        loadBundledJS(named: "markdownobserver-inline-diff")
    }

    static var scrollSyncObserverJavaScript: String {
        loadBundledJS(named: "markdownobserver-scroll-sync")
    }

    static let themeJSBootstrapScript = """
    <script>
    (function() {
      var meta = document.querySelector('meta[name="minimark-runtime-theme-js-base64"]');
      if (!meta) return;
      var b64 = meta.getAttribute('content');
      if (!b64) return;
      try {
        var binary = atob(b64);
        var bytes = Uint8Array.from(binary, function(c) { return c.charCodeAt(0); });
        var themeJS = new TextDecoder().decode(bytes);
        new Function(themeJS)();
        window.__minimarkLastThemeJSBase64 = b64;
      } catch(e) { console.error('Theme JS bootstrap error:', e); }
    })();
    </script>
    """
}
