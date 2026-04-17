import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct ReaderPreferencesStoreTests {
    @MainActor
    private final class RecordingCoordinator: ChildStoreCoordinating {
        private(set) var coalescingCalls: [Bool] = []

        func childStoreDidMutate(coalescePersistence: Bool) {
            coalescingCalls.append(coalescePersistence)
        }
    }

    @MainActor private func makeStore(_ overrides: (inout ReaderPreferencesSlice) -> Void = { _ in }) -> (PreferencesStore, RecordingCoordinator) {
        var slice = ReaderPreferencesSlice(
            appAppearance: .system,
            readerTheme: .blackOnWhite,
            syntaxTheme: .monokai,
            baseFontSize: 15,
            autoRefreshOnExternalChange: true,
            notificationsEnabled: true,
            multiFileDisplayMode: .sidebarLeft,
            sidebarSortMode: .openOrder,
            sidebarGroupSortMode: .lastChangedNewestFirst,
            diffBaselineLookback: .twoMinutes,
            dismissedHints: []
        )
        overrides(&slice)
        let store = PreferencesStore(initial: slice)
        let coordinator = RecordingCoordinator()
        store.coordinator = coordinator
        return (store, coordinator)
    }

    @Test @MainActor func updateThemeNotifiesCoordinatorWithCoalescing() {
        let (store, coordinator) = makeStore()

        store.updateTheme(.newspaper)

        #expect(store.currentPreferences.readerTheme == .newspaper)
        #expect(coordinator.coalescingCalls == [true])
    }

    @Test @MainActor func updateIdenticalThemeSkipsNotification() {
        let (store, coordinator) = makeStore { $0.readerTheme = .newspaper }

        store.updateTheme(.newspaper)

        #expect(coordinator.coalescingCalls.isEmpty)
    }

    @Test @MainActor func updateBaseFontSizeClampsBelowMinimum() {
        let (store, _) = makeStore()

        store.updateBaseFontSize(5)

        #expect(store.currentPreferences.baseFontSize == PreferencesStore.minimumFontSize)
    }

    @Test @MainActor func updateBaseFontSizeClampsAboveMaximum() {
        let (store, _) = makeStore()

        store.updateBaseFontSize(999)

        #expect(store.currentPreferences.baseFontSize == PreferencesStore.maximumFontSize)
    }

    @Test @MainActor func increaseDecreaseAndResetFontSize() {
        let (store, _) = makeStore { $0.baseFontSize = 15 }

        store.increaseFontSize(step: 2)
        #expect(store.currentPreferences.baseFontSize == 17)

        store.decreaseFontSize(step: 5)
        #expect(store.currentPreferences.baseFontSize == 12)

        store.resetFontSize()
        #expect(store.currentPreferences.baseFontSize == ReaderSettings.default.baseFontSize)
    }

    @Test @MainActor func dismissHintUsesImmediatePersistence() {
        let (store, coordinator) = makeStore()

        store.dismissHint(.multiSelect)

        #expect(store.isHintDismissed(.multiSelect))
        #expect(coordinator.coalescingCalls == [false])
    }

    @Test @MainActor func dismissAlreadyDismissedHintIsNoOp() {
        let (store, coordinator) = makeStore { $0.dismissedHints = [.multiSelect] }

        store.dismissHint(.multiSelect)

        #expect(coordinator.coalescingCalls.isEmpty)
    }

    @Test @MainActor func appearancePreferenceAndSortModeUpdatesAreCoalesced() {
        let (store, coordinator) = makeStore()

        store.updateAppAppearance(.dark)
        store.updateNotificationsEnabled(false)
        store.updateMultiFileDisplayMode(.sidebarRight)
        store.updateSidebarSortMode(.nameAscending)
        store.updateSidebarGroupSortMode(.nameAscending)
        store.updateDiffBaselineLookback(.tenMinutes)
        store.updateSyntaxTheme(.github)

        #expect(coordinator.coalescingCalls == [true, true, true, true, true, true, true])
        #expect(store.currentPreferences.appAppearance == .dark)
        #expect(store.currentPreferences.notificationsEnabled == false)
        #expect(store.currentPreferences.multiFileDisplayMode == .sidebarRight)
        #expect(store.currentPreferences.sidebarSortMode == .nameAscending)
        #expect(store.currentPreferences.sidebarGroupSortMode == .nameAscending)
        #expect(store.currentPreferences.diffBaselineLookback == .tenMinutes)
        #expect(store.currentPreferences.syntaxTheme == .github)
    }
}
