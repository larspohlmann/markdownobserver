import XCTest

/// Sandbox isolation for UI test runs.
///
/// UI tests launch the real `MarkdownObserver.app` bundle. Without this helper the app
/// would read and write the installed user's `UserDefaults` domain (favorites, recents,
/// settings) because local builds share `APP_BUNDLE_IDENTIFIER` with the installed app.
/// Setting `MINIMARK_EPHEMERAL_DEFAULTS=1` makes the app back its `SettingsStore` with
/// an in-memory key-value store for the life of the launched process.
enum UITestSandbox {
    static let ephemeralDefaultsEnvironmentKey = "MINIMARK_EPHEMERAL_DEFAULTS"

    static func apply(to app: XCUIApplication) {
        app.launchEnvironment[ephemeralDefaultsEnvironmentKey] = "1"
    }
}

extension XCUIApplication {
    /// Launch the app with test state sandboxed from the installed app's `UserDefaults`.
    /// Use this in place of `launch()` in every UI test.
    func launchSandboxed() {
        UITestSandbox.apply(to: self)
        launch()
    }
}
