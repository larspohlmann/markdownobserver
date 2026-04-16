import SwiftUI

struct ChangeNavigationOverlayView: View {
    let canNavigate: Bool
    let currentIndex: Int?
    let totalCount: Int
    let topPadding: CGFloat
    let colorScheme: ColorScheme
    let settingsStore: ReaderSettingsStore
    let onNavigate: (ReaderChangedRegionNavigationDirection) -> Void

    var body: some View {
        if canNavigate {
            ChangeNavigationPill(
                currentIndex: currentIndex,
                totalCount: totalCount,
                onNavigate: onNavigate
            )
            .firstUseHint(.changeNavigation,
                          message: "Use the arrows to step through changes",
                          settingsStore: settingsStore)
            .padding(.top, topPadding)
            .padding(.leading, 8)
            .environment(\.colorScheme, colorScheme)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity
            ))
        }
    }
}
