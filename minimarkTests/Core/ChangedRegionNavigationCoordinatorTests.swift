import Testing
@testable import minimark

@Suite
struct ChangedRegionNavigationCoordinatorTests {

    @Test func initialStateHasNoRequest() {
        let coordinator = ChangedRegionNavigationCoordinator()
        #expect(coordinator.currentIndex == nil)
        #expect(coordinator.currentRequest == nil)
    }

    @Test func requestIncreasesIDAndSetsDirection() {
        var coordinator = ChangedRegionNavigationCoordinator()
        coordinator.requestNavigation(.next)
        let request = coordinator.currentRequest
        #expect(request != nil)
        #expect(request?.direction == .next)
        #expect(request?.id == 1)
    }

    @Test func consecutiveRequestsIncrementID() {
        var coordinator = ChangedRegionNavigationCoordinator()
        coordinator.requestNavigation(.next)
        coordinator.requestNavigation(.previous)
        #expect(coordinator.currentRequest?.id == 2)
        #expect(coordinator.currentRequest?.direction == .previous)
    }

    @Test func handleResultUpdatesCurrentIndex() {
        var coordinator = ChangedRegionNavigationCoordinator()
        coordinator.requestNavigation(.next)
        coordinator.handleNavigationResult(index: 2, total: 5)
        #expect(coordinator.currentIndex == 2)
    }

    @Test func resetOnRegionsChangeClearsIndex() {
        var coordinator = ChangedRegionNavigationCoordinator()
        coordinator.requestNavigation(.next)
        coordinator.handleNavigationResult(index: 1, total: 3)
        coordinator.resetForNewRegions()
        #expect(coordinator.currentIndex == nil)
    }

    @Test func resetClearsAllState() {
        var coordinator = ChangedRegionNavigationCoordinator()
        coordinator.requestNavigation(.next)
        coordinator.handleNavigationResult(index: 0, total: 3)
        coordinator.reset()
        #expect(coordinator.currentIndex == nil)
        #expect(coordinator.currentRequest == nil)
    }
}
