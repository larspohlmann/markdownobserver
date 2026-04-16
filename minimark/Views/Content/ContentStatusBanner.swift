import SwiftUI

struct ContentStatusBanner: View {
    let isCurrentFileMissing: Bool
    let fileDisplayName: String
    let errorMessage: String?
    let needsImageDirectoryAccess: Bool
    let topPadding: CGFloat
    let onGrantImageAccess: () -> Void

    var body: some View {
        if isCurrentFileMissing {
            DeletedFileWarningBar(fileName: fileDisplayName, message: errorMessage)
                .padding(.top, topPadding)
        } else if needsImageDirectoryAccess {
            ImageAccessWarningBar(onGrantAccess: onGrantImageAccess)
                .padding(.top, topPadding)
        }
    }
}
