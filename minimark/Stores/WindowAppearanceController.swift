import Combine
import Foundation

@MainActor
final class WindowAppearanceController: ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var effectiveTheme: ReaderThemeKind
    @Published private(set) var effectiveFontSize: Double
    @Published private(set) var effectiveSyntaxTheme: SyntaxThemeKind

    private nonisolated(unsafe) static var _lockedWindowCount = 0
    static var lockedWindowCount: Int { _lockedWindowCount }

    /// Tracks whether this instance contributed to `_lockedWindowCount`.
    /// Must be `nonisolated(unsafe)` so `deinit` (which is nonisolated) can read it.
    private nonisolated(unsafe) var _isLockedForDeinit = false

    private let settingsStore: ReaderSettingsReading
    private var cancellable: AnyCancellable?

    init(settingsStore: ReaderSettingsReading) {
        self.settingsStore = settingsStore
        let current = settingsStore.currentSettings
        self.effectiveTheme = current.readerTheme
        self.effectiveFontSize = current.baseFontSize
        self.effectiveSyntaxTheme = current.syntaxTheme

        cancellable = settingsStore.settingsPublisher
            .dropFirst()
            .sink { [weak self] settings in
                guard let self, !self.isLocked else { return }
                self.effectiveTheme = settings.readerTheme
                self.effectiveFontSize = settings.baseFontSize
                self.effectiveSyntaxTheme = settings.syntaxTheme
            }
    }

    deinit {
        if _isLockedForDeinit {
            Self._lockedWindowCount -= 1
        }
    }

    func lock() {
        guard !isLocked else { return }
        isLocked = true
        _isLockedForDeinit = true
        Self._lockedWindowCount += 1
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        _isLockedForDeinit = false
        Self._lockedWindowCount -= 1

        let current = settingsStore.currentSettings
        effectiveTheme = current.readerTheme
        effectiveFontSize = current.baseFontSize
        effectiveSyntaxTheme = current.syntaxTheme
    }

    func restore(from appearance: LockedAppearance) {
        effectiveTheme = appearance.readerTheme
        effectiveFontSize = appearance.baseFontSize
        effectiveSyntaxTheme = appearance.syntaxTheme

        if !isLocked {
            isLocked = true
            _isLockedForDeinit = true
            Self._lockedWindowCount += 1
        }
    }

    var lockedAppearance: LockedAppearance? {
        guard isLocked else { return nil }
        return LockedAppearance(
            readerTheme: effectiveTheme,
            baseFontSize: effectiveFontSize,
            syntaxTheme: effectiveSyntaxTheme
        )
    }
}
