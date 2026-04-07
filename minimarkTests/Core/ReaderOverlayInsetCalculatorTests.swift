import CoreGraphics
import Testing
@testable import minimark

@Suite
struct ReaderOverlayInsetCalculatorTests {
    @Test func computesInsetsForTopBarOnly() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 98)
    }

    @Test func computesInsetsWhenSourceEditBarAndWarningBarAreVisible() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 54)
    }

    @Test func clampsNegativeBannerHeightToZero() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 98)
    }

    @Test func ignoresTopBarInsetWhenStatusBannerIsVisible() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 54)
    }

    @Test func statusBannerTopPaddingMatchesTopBarInset() {
        let padding = ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: 66)
        #expect(padding == 66)
    }

    @Test func statusBannerTopPaddingClampsNegativeInset() {
        let padding = ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: -10)
        #expect(padding == 0)
    }
}
