import Foundation
import Combine
import Observation

nonisolated struct ReaderPreferencesSlice: Equatable, Sendable {
    var appAppearance: AppAppearance
    var readerTheme: ThemeKind
    var syntaxTheme: SyntaxThemeKind
    var baseFontSize: Double
    var autoRefreshOnExternalChange: Bool
    var notificationsEnabled: Bool
    var multiFileDisplayMode: MultiFileDisplayMode
    var sidebarSortMode: SidebarSortMode
    var sidebarGroupSortMode: SidebarSortMode
    var diffBaselineLookback: DiffBaselineLookback
    var dismissedHints: Set<FirstUseHint>
}

@MainActor @Observable final class PreferencesStore: ThemeWriting, PreferencesWriting, HintWriting {
    static let minimumFontSize: Double = 10
    static let maximumFontSize: Double = 48

    private(set) var currentPreferences: ReaderPreferencesSlice

    weak var coordinator: ChildStoreCoordinating?

    @ObservationIgnored
    private let subject: CurrentValueSubject<ReaderPreferencesSlice, Never>

    var preferencesPublisher: AnyPublisher<ReaderPreferencesSlice, Never> {
        subject.eraseToAnyPublisher()
    }

    init(initial: ReaderPreferencesSlice) {
        self.currentPreferences = initial
        self.subject = CurrentValueSubject(initial)
    }

    func updateAppAppearance(_ appearance: AppAppearance) {
        mutate(coalescePersistence: true) { slice in
            slice.appAppearance = appearance
        }
    }

    func updateTheme(_ kind: ThemeKind) {
        mutate(coalescePersistence: true) { slice in
            slice.readerTheme = kind
        }
    }

    func updateSyntaxTheme(_ kind: SyntaxThemeKind) {
        mutate(coalescePersistence: true) { slice in
            slice.syntaxTheme = kind
        }
    }

    func updateBaseFontSize(_ value: Double) {
        let clamped = min(max(value, Self.minimumFontSize), Self.maximumFontSize)
        mutate(coalescePersistence: true) { slice in
            slice.baseFontSize = clamped
        }
    }

    func increaseFontSize(step: Double) {
        updateBaseFontSize(currentPreferences.baseFontSize + step)
    }

    func decreaseFontSize(step: Double) {
        updateBaseFontSize(currentPreferences.baseFontSize - step)
    }

    func resetFontSize() {
        updateBaseFontSize(ReaderSettings.default.baseFontSize)
    }

    func updateNotificationsEnabled(_ isEnabled: Bool) {
        mutate(coalescePersistence: true) { slice in
            slice.notificationsEnabled = isEnabled
        }
    }

    func updateMultiFileDisplayMode(_ mode: MultiFileDisplayMode) {
        mutate(coalescePersistence: true) { slice in
            slice.multiFileDisplayMode = mode
        }
    }

    func updateSidebarSortMode(_ mode: SidebarSortMode) {
        mutate(coalescePersistence: true) { slice in
            slice.sidebarSortMode = mode
        }
    }

    func updateSidebarGroupSortMode(_ mode: SidebarSortMode) {
        mutate(coalescePersistence: true) { slice in
            slice.sidebarGroupSortMode = mode
        }
    }

    func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback) {
        mutate(coalescePersistence: true) { slice in
            slice.diffBaselineLookback = lookback
        }
    }

    func isHintDismissed(_ hint: FirstUseHint) -> Bool {
        currentPreferences.dismissedHints.contains(hint)
    }

    func dismissHint(_ hint: FirstUseHint) {
        mutate(coalescePersistence: false) { slice in
            slice.dismissedHints.insert(hint)
        }
    }

    private func mutate(
        coalescePersistence: Bool,
        _ transform: (inout ReaderPreferencesSlice) -> Void
    ) {
        var updated = currentPreferences
        transform(&updated)
        guard updated != currentPreferences else {
            return
        }
        currentPreferences = updated
        subject.send(updated)
        coordinator?.childStoreDidMutate(coalescePersistence: coalescePersistence)
    }
}
