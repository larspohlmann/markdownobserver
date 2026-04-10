import Testing
@testable import minimark

@Suite
struct ChangeNavigationPillTests {

    // MARK: - Counter text

    @Test func counterShowsDashBeforeFirstNavigation() {
        let text = ChangeNavigationPill.counterText(currentIndex: nil, totalCount: 3)
        #expect(text == "\u{2014} / 3")
    }

    @Test func counterShowsOneBasedIndex() {
        #expect(ChangeNavigationPill.counterText(currentIndex: 0, totalCount: 3) == "1 / 3")
        #expect(ChangeNavigationPill.counterText(currentIndex: 1, totalCount: 3) == "2 / 3")
        #expect(ChangeNavigationPill.counterText(currentIndex: 2, totalCount: 3) == "3 / 3")
    }

    @Test func counterClampsIndexToValidRange() {
        #expect(ChangeNavigationPill.counterText(currentIndex: 5, totalCount: 3) == "3 / 3")
    }

    @Test func counterHandlesSingleChange() {
        #expect(ChangeNavigationPill.counterText(currentIndex: nil, totalCount: 1) == "\u{2014} / 1")
        #expect(ChangeNavigationPill.counterText(currentIndex: 0, totalCount: 1) == "1 / 1")
    }

    // MARK: - Wrap-around navigation index

    @Test func nextFromLastWrapsToFirst() {
        let index = wrappedIndex(current: 2, count: 3, direction: .next)
        #expect(index == 0)
    }

    @Test func previousFromFirstWrapsToLast() {
        let index = wrappedIndex(current: 0, count: 3, direction: .previous)
        #expect(index == 2)
    }

    @Test func nextAdvancesNormally() {
        #expect(wrappedIndex(current: 0, count: 3, direction: .next) == 1)
        #expect(wrappedIndex(current: 1, count: 3, direction: .next) == 2)
    }

    @Test func previousRetreatNormally() {
        #expect(wrappedIndex(current: 2, count: 3, direction: .previous) == 1)
        #expect(wrappedIndex(current: 1, count: 3, direction: .previous) == 0)
    }

    @Test func singleChangeAlwaysWrapsToZero() {
        #expect(wrappedIndex(current: 0, count: 1, direction: .next) == 0)
        #expect(wrappedIndex(current: 0, count: 1, direction: .previous) == 0)
    }

    // MARK: - Helpers

    /// Mirrors the wrap-around logic in the JS navigateChangedRegion function.
    private func wrappedIndex(
        current: Int,
        count: Int,
        direction: ReaderChangedRegionNavigationDirection
    ) -> Int {
        switch direction {
        case .previous:
            return current <= 0 ? count - 1 : current - 1
        case .next:
            return current >= count - 1 ? 0 : current + 1
        }
    }
}
