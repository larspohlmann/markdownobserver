import SwiftUI

struct ChangeNavigationOverlayView: View {
    let state: ChangeNavigationState
    let insets: ReaderOverlayInsetValues
    let colorScheme: ColorScheme
    let settingsStore: ReaderSettingsStore
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    var body: some View {
        if state.canNavigate {
            ChangeNavigationPill(
                currentIndex: state.currentIndex,
                totalCount: state.totalCount,
                onNavigate: onNavigate
            )
            .firstUseHint(.changeNavigation,
                          message: "Use the arrows to step through changes",
                          settingsStore: settingsStore)
            .padding(.top, insets.leadingOverlayTopPadding)
            .padding(.leading, insets.changeNavigationLeadingPadding)
            .environment(\.colorScheme, colorScheme)
            .transition(.overlayPill)
        }
    }
}
