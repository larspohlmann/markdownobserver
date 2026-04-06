import Foundation

struct ChangedRegionNavigationRequest: Equatable {
    let id: Int
    let direction: ReaderChangedRegionNavigationDirection
}

struct ScrollSyncRequest: Equatable {
    let id: Int
    let progress: Double
}

struct ScrollSyncObservation: Equatable {
    let progress: Double
    let isProgrammatic: Bool
}

struct DropTargetingUpdate: Equatable {
    let isTargeted: Bool
    let droppedFileURLs: [URL]
    let containsDirectoryHint: Bool
    let canDrop: Bool
}
