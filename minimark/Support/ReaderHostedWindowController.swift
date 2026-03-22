import AppKit
import SwiftUI

@MainActor
final class ReaderHostedWindowController: NSWindowController {
    init(settingsStore: ReaderSettingsStore) {
        let hostingController = NSHostingController(
            rootView: ReaderWindowRootView(
                seed: nil,
                settingsStore: settingsStore,
                multiFileDisplayMode: settingsStore.currentSettings.multiFileDisplayMode
            )
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ReaderWindowDefaults.defaultWidth,
                height: ReaderWindowDefaults.defaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = ReaderWindowTitleFormatter.appName
        window.isReleasedWhenClosed = false

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}