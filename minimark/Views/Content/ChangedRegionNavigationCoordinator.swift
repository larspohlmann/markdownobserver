import Foundation

struct ChangedRegionNavigationCoordinator {
    private var requestID = 0
    private var lastDirection: ReaderChangedRegionNavigationDirection?
    private(set) var currentIndex: Int?

    var currentRequest: ChangedRegionNavigationRequest? {
        guard let lastDirection else { return nil }
        return ChangedRegionNavigationRequest(id: requestID, direction: lastDirection)
    }

    mutating func requestNavigation(_ direction: ReaderChangedRegionNavigationDirection) {
        lastDirection = direction
        requestID += 1
    }

    mutating func handleNavigationResult(index: Int, total: Int) {
        currentIndex = index
    }

    /// Called when changedRegions changes -- clears the current index but
    /// preserves the last direction so in-progress navigation stays coherent.
    mutating func resetForNewRegions() {
        currentIndex = nil
    }

    /// Full reset -- called on file identity change or scroll coordinator reset.
    mutating func reset() {
        requestID = 0
        lastDirection = nil
        currentIndex = nil
    }
}
