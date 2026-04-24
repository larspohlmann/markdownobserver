import Foundation
import Testing
@testable import minimark

@Suite @MainActor struct WindowAppearanceControllerOverrideTests {
    @Test func effectiveAppearanceIncludesOverrideAtConstruction() {
        let settingsStore = TestSettingsStore(autoRefreshOnExternalChange: true)
        settingsStore.updateTheme(.nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: "#AABBCC")
        settingsStore.updateReaderThemeOverride(override)

        let controller = WindowAppearanceController(settingsStore: settingsStore)

        #expect(controller.effectiveAppearance.readerThemeOverride == override)
    }

    @Test func publisherUpdatesPropagateOverrideWhenUnlocked() async {
        let settingsStore = TestSettingsStore(autoRefreshOnExternalChange: true)
        settingsStore.updateTheme(.nord)
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        settingsStore.updateReaderThemeOverride(
            ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)
        )

        _ = await waitUntil { controller.effectiveAppearance.readerThemeOverride?.backgroundHex == "#112233" }
        #expect(controller.effectiveAppearance.readerThemeOverride?.backgroundHex == "#112233")
    }

    @Test func lockedAppearanceExposesOverride() {
        let settingsStore = TestSettingsStore(autoRefreshOnExternalChange: true)
        settingsStore.updateTheme(.nord)
        let override = ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: nil)
        settingsStore.updateReaderThemeOverride(override)
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        controller.lock()

        #expect(controller.lockedAppearance?.readerThemeOverride == override)
    }

    @Test func restoreFromLockedAppearanceAppliesOverride() {
        let settingsStore = TestSettingsStore(autoRefreshOnExternalChange: true)
        settingsStore.updateTheme(.nord)
        let controller = WindowAppearanceController(settingsStore: settingsStore)
        let locked = LockedAppearance(
            readerTheme: .nord,
            baseFontSize: 16,
            syntaxTheme: .monokai,
            readerThemeOverride: ThemeOverride(themeKind: .nord, backgroundHex: "#112233", foregroundHex: "#AABBCC")
        )

        controller.restore(from: locked)

        #expect(controller.effectiveAppearance == locked)
        #expect(controller.isLocked)
    }
}
