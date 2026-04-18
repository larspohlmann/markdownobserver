import AppKit
import SwiftUI

/// UI-test-only bootstrap. Creates a tiny off-screen `NSWindow` that hosts a
/// SwiftUI view. The hosted view uses the `@Environment(\.openWindow)` action
/// to spawn a real `WindowGroup`-backed window (a first-class SwiftUI Scene),
/// then the bootstrap window closes itself.
///
/// This route matters for UI tests because scene-scoped focused values
/// (`focusedSceneValue`) only publish when the observed window is a SwiftUI
/// Scene. An `NSHostingController` inside a plain `NSWindow` wouldn't satisfy
/// that — but by using it only to trigger `openWindow`, the ensuing window is
/// a proper Scene and tests exercise the same path production uses.
@MainActor
final class HostedWindowController: NSWindowController {
    init() {
        // Placeholder root view — replaced in the `super.init` tail with one
        // that captures `self` so the bootstrap window can close itself once
        // the spawned WindowGroup scene is up.
        let hostingController = NSHostingController(rootView: HostedBootstrapRootView())

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true

        super.init(window: window)

        hostingController.rootView = HostedBootstrapRootView(onReady: { [weak self] in
            self?.close()
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct HostedBootstrapRootView: View {
    var onReady: (() -> Void)?

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                openWindow(value: WindowSeed())
                // Let SwiftUI attach and key the spawned window before we tear
                // down the bootstrap window.
                try? await Task.sleep(for: .milliseconds(200))
                onReady?()
            }
    }
}
