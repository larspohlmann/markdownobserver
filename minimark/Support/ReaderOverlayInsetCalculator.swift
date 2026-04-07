import CoreGraphics

struct ReaderOverlayInsetValues: Equatable {
    let railTopPadding: CGFloat
    let leadingOverlayTopPadding: CGFloat
    let scrollTargetTopInset: CGFloat
}

enum ReaderOverlayInsetCalculator {
    static let overlayBaseGap: CGFloat = 8
    static let leadingOverlayAlignmentAdjustment: CGFloat = 8
    static let overlayControlHeight: CGFloat = 30
    static let scrollLandingGap: CGFloat = 8

    static func statusBannerTopPadding(topBarInset: CGFloat) -> CGFloat {
        max(0, topBarInset)
    }

    static func compute(topBarInset: CGFloat, hasStatusBanner: Bool) -> ReaderOverlayInsetValues {
        let safeTopBarInset = max(0, topBarInset)
        let overlayBaseInset = (hasStatusBanner ? 0 : safeTopBarInset) + overlayBaseGap
        let railTopPadding = overlayBaseInset
        let leadingOverlayTopPadding = overlayBaseInset + leadingOverlayAlignmentAdjustment
        let scrollTargetTopInset = leadingOverlayTopPadding + overlayControlHeight + scrollLandingGap

        return ReaderOverlayInsetValues(
            railTopPadding: railTopPadding,
            leadingOverlayTopPadding: leadingOverlayTopPadding,
            scrollTargetTopInset: scrollTargetTopInset
        )
    }
}
