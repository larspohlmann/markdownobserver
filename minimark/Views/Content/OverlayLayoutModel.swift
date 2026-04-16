import CoreGraphics
import Foundation

struct OverlayLayoutModel: Equatable, Sendable {
    let isSourceEditing: Bool
    let isStatusBannerVisible: Bool

    var topInset: CGFloat {
        var height = ReaderTopBarMetrics.mainBarHeight
        if isSourceEditing {
            height += ReaderTopBarMetrics.sourceEditingBarHeight
        }
        return height
    }

    var insets: ReaderOverlayInsetValues {
        ReaderOverlayInsetCalculator.compute(
            topBarInset: topInset,
            hasStatusBanner: isStatusBannerVisible
        )
    }

    var statusBannerTopPadding: CGFloat {
        ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: topInset)
    }
}
