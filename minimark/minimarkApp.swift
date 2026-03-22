import AppKit
import SwiftUI

@main
struct MarkdownObserverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: ReaderSettingsStore

    init() {
        let settingsStore = ReaderSettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        ReaderUITestWindowBootstrapper.shared.configure(settingsStore: settingsStore)

        ReaderSystemNotifier.shared.configure()

        NSWindow.allowsAutomaticWindowTabbing = false
        applyAppAppearanceIfAvailable(settingsStore.currentSettings.appAppearance)
    }

    var body: some Scene {
        let activeMultiFileDisplayMode = settingsStore.currentSettings.multiFileDisplayMode
        let appAppearance = settingsStore.currentSettings.appAppearance

        WindowGroup("MarkdownObserver", for: ReaderWindowSeed.self) { seed in
            ReaderWindowRootView(
                seed: seed.wrappedValue,
                settingsStore: settingsStore,
                multiFileDisplayMode: activeMultiFileDisplayMode
            )
            .appAppearance(appAppearance)
        }
        .defaultSize(
            width: ReaderWindowDefaults.defaultWidth,
            height: ReaderWindowDefaults.defaultHeight
        )
        .commands {
            ReaderCommands(settingsStore: settingsStore, multiFileDisplayMode: activeMultiFileDisplayMode)
        }

        Settings {
            ReaderSettingsView(settingsStore: settingsStore)
            .appAppearance(appAppearance)
        }
        .defaultSize(width: 640, height: 700)
        .windowResizability(.contentSize)

        Window("About MarkdownObserver", id: AppWindowID.about.rawValue) {
            AboutWindowView()
                .appAppearance(appAppearance)
        }
        .windowResizability(.contentSize)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ReaderUITestWindowBootstrapper.shared.openInitialWindowIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        ReaderSystemNotifier.shared.refreshNotificationStatus()
    }
}

@MainActor
private final class ReaderUITestWindowBootstrapper {
    static let shared = ReaderUITestWindowBootstrapper()

    private var settingsStore: ReaderSettingsStore?
    private var windowController: ReaderHostedWindowController?

    func configure(settingsStore: ReaderSettingsStore) {
        self.settingsStore = settingsStore
    }

    func openInitialWindowIfNeeded() {
        guard ReaderUITestLaunchConfiguration.current.isUITestModeEnabled else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self,
                  let settingsStore = self.settingsStore,
                  NSApp.windows.isEmpty else {
                return
            }

            let controller = ReaderHostedWindowController(settingsStore: settingsStore)
            windowController = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct AppAppearanceModifier: ViewModifier {
    let appAppearance: AppAppearance

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appAppearance.colorScheme)
            .task(id: appAppearance) {
                applyAppAppearanceIfAvailable(appAppearance)
            }
    }
}

@MainActor
private func applyAppAppearanceIfAvailable(_ appAppearance: AppAppearance) {
    NSApp?.appearance = appAppearance.nsAppearance
}

private extension View {
    func appAppearance(_ appAppearance: AppAppearance) -> some View {
        modifier(AppAppearanceModifier(appAppearance: appAppearance))
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}
