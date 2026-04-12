import WebKit

@MainActor
final class WebKitWarmup {
    static let shared = WebKitWarmup()

    private(set) var hasWarmedUp = false

    func warmUp() {
        guard !hasWarmedUp else { return }
        hasWarmedUp = true

        // Creating a WKWebView triggers web content process spawn.
        // Subsequent WKWebView creations reuse the running process,
        // avoiding the cold-start cost. The throwaway view is released
        // immediately — only the process spawn matters.
        _ = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    }
}
