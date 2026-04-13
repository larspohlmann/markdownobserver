import Foundation

enum DocumentSurfaceAction {
    case fatalCrash
    case postLoadStatus(String?)
    case scrollSyncObservation(ScrollSyncObservation)
    case sourceEdit(String)
    case tocHeadingsExtracted([TOCHeading])
    case droppedFileURLs([URL])
    case dropTargetedChange(DropTargetingUpdate)
    case changedRegionNavigationResult(index: Int, total: Int)
    case retryFallback
}

enum DocumentSurfaceRole: Hashable {
    case preview
    case source

    var counterpart: DocumentSurfaceRole {
        switch self {
        case .preview:
            return .source
        case .source:
            return .preview
        }
    }
}

struct DocumentSurfaceConfiguration {
    let role: DocumentSurfaceRole
    let usesWebSurface: Bool
    let htmlDocument: String
    let documentIdentity: String?
    let accessibilityIdentifier: String
    let accessibilityValue: String
    let reloadToken: Int
    let diagnosticName: String
    let postLoadStatusScript: String?
    let changedRegionNavigationRequest: ChangedRegionNavigationRequest?
    let scrollSyncRequest: ScrollSyncRequest?
    let tocScrollRequest: TOCScrollRequest?
    let supportsInPlaceContentUpdates: Bool
    let overlayTopInset: CGFloat
    let reloadAnchorProgress: Double?
    let minimumWidth: CGFloat?
    let canAcceptDroppedFileURLs: ([URL]) -> Bool
    let onAction: (DocumentSurfaceAction) -> Void
}
