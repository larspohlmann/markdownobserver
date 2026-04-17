import CoreGraphics
import Testing
@testable import minimark

@Suite
struct ReaderOverlayInsetCalculatorTests {
    private var gap: CGFloat { ReaderOverlayInsetCalculator.scrollLandingGap }

    @Test func computesInsetsForTopBarOnly() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 60 + 30 + gap)
    }

    @Test func computesInsetsWhenSourceEditBarAndWarningBarAreVisible() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 16 + 30 + gap)
    }

    @Test func clampsNegativeBannerHeightToZero() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 60 + 30 + gap)
    }

    @Test func ignoresTopBarInsetWhenStatusBannerIsVisible() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 16 + 30 + gap)
    }

    @Test func statusBannerTopPaddingMatchesTopBarInset() {
        let padding = ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: 66)
        #expect(padding == 66)
    }

    @Test func statusBannerTopPaddingClampsNegativeInset() {
        let padding = ReaderOverlayInsetCalculator.statusBannerTopPadding(topBarInset: -10)
        #expect(padding == 0)
    }

    @Test func emitsWatchPillLeadingWithChangeNav() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillLeadingWithChangeNav == 150)
    }

    @Test func emitsWatchPillLeadingWithoutChangeNav() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillLeadingWithoutChangeNav == 60)
    }

    @Test func emitsWatchPillTrailing() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillTrailing == 70)
    }

    @Test func changeNavigationLeadingPaddingMatchesLeadingAlignmentAdjustment() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.changeNavigationLeadingPadding == ReaderOverlayInsetCalculator.leadingOverlayAlignmentAdjustment)
    }

    @Test func watchPillAndChangeNavInsetsAreConstantAcrossTopBarConfigurations() {
        let withBanner = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )
        let withoutBanner = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(withBanner.watchPillLeadingWithChangeNav == withoutBanner.watchPillLeadingWithChangeNav)
        #expect(withBanner.watchPillLeadingWithoutChangeNav == withoutBanner.watchPillLeadingWithoutChangeNav)
        #expect(withBanner.watchPillTrailing == withoutBanner.watchPillTrailing)
        #expect(withBanner.changeNavigationLeadingPadding == withoutBanner.changeNavigationLeadingPadding)
    }
}
