import WebKit

@MainActor
final class WebKitWarmup {
    static let shared = WebKitWarmup()

    private(set) var processPool: WKProcessPool?

    func warmUp() {
        guard processPool == nil else { return }
        let pool = WKProcessPool()
        processPool = pool

        let configuration = WKWebViewConfiguration()
        configuration.processPool = pool
        // Creating the WKWebView triggers web content process spawn.
        // We don't need to keep it -- the pool retains the process.
        _ = WKWebView(frame: .zero, configuration: configuration)
    }
}
