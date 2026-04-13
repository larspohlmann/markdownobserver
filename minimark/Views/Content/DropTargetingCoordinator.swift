import Foundation

struct DropTargetingCoordinator {
    private var dragTargetedSurfaces: Set<DocumentSurfaceRole> = []
    private var blockedFolderDropTargetedSurfaces: Set<DocumentSurfaceRole> = []

    var isDragTargeted: Bool { !dragTargetedSurfaces.isEmpty }
    var isBlockedFolderDropTargeted: Bool { !blockedFolderDropTargetedSurfaces.isEmpty }

    mutating func update(for surface: DocumentSurfaceRole, update: DropTargetingUpdate) {
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

    mutating func clear(for surface: DocumentSurfaceRole) {
        dragTargetedSurfaces.remove(surface)
        blockedFolderDropTargetedSurfaces.remove(surface)
    }

    mutating func clearAll() {
        dragTargetedSurfaces.removeAll()
        blockedFolderDropTargetedSurfaces.removeAll()
    }
}
