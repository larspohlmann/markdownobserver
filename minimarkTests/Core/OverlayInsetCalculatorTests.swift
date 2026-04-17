import CoreGraphics
import Testing
@testable import minimark

@Suite
struct OverlayInsetCalculatorTests {
    private var gap: CGFloat { OverlayInsetCalculator.scrollLandingGap }

    @Test func computesInsetsForTopBarOnly() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 60 + 30 + gap)
    }

    @Test func computesInsetsWhenSourceEditBarAndWarningBarAreVisible() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 16 + 30 + gap)
    }

    @Test func clampsNegativeBannerHeightToZero() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 60 + 30 + gap)
    }

    @Test func ignoresTopBarInsetWhenStatusBannerIsVisible() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )

        #expect(result.railTopPadding == 8)
        #expect(result.leadingOverlayTopPadding == 16)
        #expect(result.scrollTargetTopInset == 16 + 30 + gap)
    }

    @Test func statusBannerTopPaddingMatchesTopBarInset() {
        let padding = OverlayInsetCalculator.statusBannerTopPadding(topBarInset: 66)
        #expect(padding == 66)
    }

    @Test func statusBannerTopPaddingClampsNegativeInset() {
        let padding = OverlayInsetCalculator.statusBannerTopPadding(topBarInset: -10)
        #expect(padding == 0)
    }

    @Test func emitsWatchPillLeadingWithChangeNav() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillLeadingWithChangeNav == 150)
    }

    @Test func emitsWatchPillLeadingWithoutChangeNav() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillLeadingWithoutChangeNav == 60)
    }

    @Test func emitsWatchPillTrailing() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.watchPillTrailing == 70)
    }

    @Test func emitsChangeNavigationLeadingPadding() {
        let result = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(result.changeNavigationLeadingPadding == 8)
    }

    @Test func watchPillAndChangeNavInsetsAreConstantAcrossTopBarConfigurations() {
        let withBanner = OverlayInsetCalculator.compute(
            topBarInset: 66,
            hasStatusBanner: true
        )
        let withoutBanner = OverlayInsetCalculator.compute(
            topBarInset: 44,
            hasStatusBanner: false
        )

        #expect(withBanner.watchPillLeadingWithChangeNav == withoutBanner.watchPillLeadingWithChangeNav)
        #expect(withBanner.watchPillLeadingWithoutChangeNav == withoutBanner.watchPillLeadingWithoutChangeNav)
        #expect(withBanner.watchPillTrailing == withoutBanner.watchPillTrailing)
        #expect(withBanner.changeNavigationLeadingPadding == withoutBanner.changeNavigationLeadingPadding)
    }
}
