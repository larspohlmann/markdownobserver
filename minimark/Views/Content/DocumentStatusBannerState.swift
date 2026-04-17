import Foundation

struct DocumentStatusBannerState: Equatable {
    let isCurrentFileMissing: Bool
    let fileDisplayName: String
    let errorMessage: String?
    let needsImageDirectoryAccess: Bool
}
