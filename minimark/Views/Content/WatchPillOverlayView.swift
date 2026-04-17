import SwiftUI

struct WatchPillOverlayView: View {
    let activeFolderWatch: FolderWatchSession?
    let isCurrentWatchAFavorite: Bool
    let canStop: Bool
    let isAppearanceLocked: Bool
    let topPadding: CGFloat
    let leadingPadding: CGFloat
    let trailingPadding: CGFloat
    let colorScheme: ColorScheme
    let onAction: (WatchPillAction) -> Void

    var body: some View {
        if let activeWatch = activeFolderWatch {
            WatchPill(
                activeFolderWatch: activeWatch,
                isCurrentWatchAFavorite: isCurrentWatchAFavorite,
                canStop: canStop,
                isAppearanceLocked: isAppearanceLocked,
                onAction: onAction
            )
            .padding(.top, topPadding)
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .environment(\.colorScheme, colorScheme)
            .transition(.overlayPill)
        }
    }
}
