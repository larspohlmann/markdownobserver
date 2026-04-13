import Testing
@testable import minimark

@Suite
struct DropTargetingCoordinatorTests {

    @Test func initialStateIsNotTargeted() {
        let coordinator = DropTargetingCoordinator()
        #expect(!coordinator.isDragTargeted)
        #expect(!coordinator.isBlockedFolderDropTargeted)
    }

    @Test func targetingSurfaceMarksDragTargeted() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        #expect(coordinator.isDragTargeted)
    }

    @Test func untargetingSurfaceClearsDragTargeted() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        coordinator.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: false, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        #expect(!coordinator.isDragTargeted)
    }

    @Test func blockedFolderDropIsTracked() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: true, canDrop: false)
        )
        #expect(coordinator.isBlockedFolderDropTargeted)
    }

    @Test func clearForSurfaceRemovesOnlyThatSurface() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        coordinator.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        coordinator.clear(for: .preview)
        #expect(coordinator.isDragTargeted) // source still targeted
    }

    @Test func untargetingBlockedFolderDropClearsBlockedState() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: true, canDrop: false)
        )
        coordinator.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: false, droppedFileURLs: [], containsDirectoryHint: true, canDrop: false)
        )
        #expect(!coordinator.isBlockedFolderDropTargeted)
    }

    @Test func clearAllRemovesAllSurfaces() {
        var coordinator = DropTargetingCoordinator()
        coordinator.update(
            for: .preview,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: false, canDrop: true)
        )
        coordinator.update(
            for: .source,
            update: DropTargetingUpdate(isTargeted: true, droppedFileURLs: [], containsDirectoryHint: true, canDrop: false)
        )
        coordinator.clearAll()
        #expect(!coordinator.isDragTargeted)
        #expect(!coordinator.isBlockedFolderDropTargeted)
    }
}
