import Foundation
import Testing
@testable import minimark

@Suite
struct OverlayLayoutModelTests {

    @Test func topInsetWithoutSourceEditingIsMainBarHeight() {
        let model = OverlayLayoutModel(isSourceEditing: false, isStatusBannerVisible: false)
        #expect(model.topInset == ReaderTopBarMetrics.mainBarHeight)
    }

    @Test func topInsetWithSourceEditingAddsSourceBarHeight() {
        let model = OverlayLayoutModel(isSourceEditing: true, isStatusBannerVisible: false)
        #expect(model.topInset == ReaderTopBarMetrics.mainBarHeight + ReaderTopBarMetrics.sourceEditingBarHeight)
    }

    @Test func insetsDelegateToCalculator() {
        let model = OverlayLayoutModel(isSourceEditing: false, isStatusBannerVisible: true)
        let expected = OverlayInsetCalculator.compute(
            topBarInset: ReaderTopBarMetrics.mainBarHeight,
            hasStatusBanner: true
        )
        #expect(model.insets == expected)
    }

    @Test func statusBannerPaddingDelegatesToCalculator() {
        let model = OverlayLayoutModel(isSourceEditing: true, isStatusBannerVisible: false)
        let expected = OverlayInsetCalculator.statusBannerTopPadding(
            topBarInset: ReaderTopBarMetrics.mainBarHeight + ReaderTopBarMetrics.sourceEditingBarHeight
        )
        #expect(model.statusBannerTopPadding == expected)
    }
}
