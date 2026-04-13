import Foundation

struct DropTargetingCoordinator {
    private var dragTargetedSurfaces: Set<ContentView.DocumentSurfaceRole> = []
    private var blockedFolderDropTargetedSurfaces: Set<ContentView.DocumentSurfaceRole> = []

    var isDragTargeted: Bool { !dragTargetedSurfaces.isEmpty }
    var isBlockedFolderDropTargeted: Bool { !blockedFolderDropTargetedSurfaces.isEmpty }

    mutating func update(for surface: ContentView.DocumentSurfaceRole, update: DropTargetingUpdate) {
        if update.isTargeted {
            dragTargetedSurfaces.insert(surface)
        } else {
            dragTargetedSurfaces.remove(surface)
        }

        let isBlockedFolderDrop = update.isTargeted && !update.canDrop && update.containsDirectoryHint
        if isBlockedFolderDrop {
            blockedFolderDropTargetedSurfaces.insert(surface)
        } else {
            blockedFolderDropTargetedSurfaces.remove(surface)
        }
    }

    mutating func clear(for surface: ContentView.DocumentSurfaceRole) {
        dragTargetedSurfaces.remove(surface)
        blockedFolderDropTargetedSurfaces.remove(surface)
    }

    mutating func clearAll() {
        dragTargetedSurfaces.removeAll()
        blockedFolderDropTargetedSurfaces.removeAll()
    }
}
