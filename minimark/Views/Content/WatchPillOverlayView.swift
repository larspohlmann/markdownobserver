import SwiftUI

struct WatchPillOverlayView: View {
    let state: WatchPillState
    let insets: OverlayInsetValues
    let hasChangeNavigation: Bool
    let colorScheme: ColorScheme
    let onAction: (WatchPillAction) -> Void

    var body: some View {
        if let activeWatch = state.activeFolderWatch {
            WatchPill(
                activeFolderWatch: activeWatch,
                isCurrentWatchAFavorite: state.isCurrentWatchAFavorite,
                canStop: state.canStop,
                isAppearanceLocked: state.isAppearanceLocked,
                onAction: onAction
            )
            .padding(.top, insets.leadingOverlayTopPadding)
            .padding(.leading, hasChangeNavigation
                ? insets.watchPillLeadingWithChangeNav
                : insets.watchPillLeadingWithoutChangeNav)
            .padding(.trailing, insets.watchPillTrailing)
            .environment(\.colorScheme, colorScheme)
            .transition(.overlayPill)
        }
    }
}
