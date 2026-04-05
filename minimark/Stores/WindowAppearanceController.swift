import Combine
import Foundation
import Synchronization

@MainActor
@Observable
final class WindowAppearanceController {
    private(set) var isLocked = false
    private(set) var effectiveAppearance: LockedAppearance

    var effectiveTheme: ReaderThemeKind { effectiveAppearance.readerTheme }
    var effectiveFontSize: Double { effectiveAppearance.baseFontSize }
    var effectiveSyntaxTheme: SyntaxThemeKind { effectiveAppearance.syntaxTheme }

    private static let _lockedWindowCount = Mutex(0)
    static var lockedWindowCount: Int { _lockedWindowCount.withLock { $0 } }

    /// Tracks whether this instance contributed to `_lockedWindowCount`.
    /// Must be `nonisolated(unsafe)` so `deinit` (which is nonisolated) can read it.
    private nonisolated(unsafe) var _isLockedForDeinit = false

    private let settingsStore: ReaderSettingsReading
    private var cancellable: AnyCancellable?

    init(settingsStore: ReaderSettingsReading) {
        self.settingsStore = settingsStore
        let current = settingsStore.currentSettings
        self.effectiveAppearance = LockedAppearance(
            readerTheme: current.readerTheme,
            baseFontSize: current.baseFontSize,
            syntaxTheme: current.syntaxTheme
        )

        cancellable = settingsStore.settingsPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self, !self.isLocked else { return }
                let newAppearance = LockedAppearance(
                    readerTheme: settings.readerTheme,
                    baseFontSize: settings.baseFontSize,
                    syntaxTheme: settings.syntaxTheme
                )
                if self.effectiveAppearance != newAppearance {
                    self.effectiveAppearance = newAppearance
                }
            }
    }

    deinit {
        if _isLockedForDeinit {
            Self._lockedWindowCount.withLock { $0 -= 1 }
        }
    }

    func lock() {
        guard !isLocked else { return }
        isLocked = true
        _isLockedForDeinit = true
        Self._lockedWindowCount.withLock { $0 += 1 }
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        _isLockedForDeinit = false
        Self._lockedWindowCount.withLock { $0 -= 1 }

        let current = settingsStore.currentSettings
        effectiveAppearance = LockedAppearance(
            readerTheme: current.readerTheme,
            baseFontSize: current.baseFontSize,
            syntaxTheme: current.syntaxTheme
        )
    }

    func restore(from appearance: LockedAppearance) {
        effectiveAppearance = appearance

        if !isLocked {
            isLocked = true
            _isLockedForDeinit = true
            Self._lockedWindowCount.withLock { $0 += 1 }
        }
    }

    var lockedAppearance: LockedAppearance? {
        guard isLocked else { return nil }
        return effectiveAppearance
    }
}
