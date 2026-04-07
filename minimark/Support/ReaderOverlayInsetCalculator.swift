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

    static func compute(topBarInset: CGFloat, statusBannerHeight: CGFloat) -> ReaderOverlayInsetValues {
        let safeTopBarInset = max(0, topBarInset)
        let safeStatusBannerHeight = max(0, statusBannerHeight)
        let overlayBaseInset = safeTopBarInset + safeStatusBannerHeight + overlayBaseGap
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
