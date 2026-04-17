import CoreGraphics

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

    var insets: OverlayInsetValues {
        OverlayInsetCalculator.compute(
            topBarInset: topInset,
            hasStatusBanner: isStatusBannerVisible
        )
    }

    var statusBannerTopPadding: CGFloat {
        OverlayInsetCalculator.statusBannerTopPadding(topBarInset: topInset)
    }
}
