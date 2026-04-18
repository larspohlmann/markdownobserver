import SwiftUI

struct ContentStatusBanner: View {
    let state: DocumentStatusBannerState
    let topPadding: CGFloat
    let onGrantImageAccess: () -> Void

    var body: some View {
        if state.isCurrentFileMissing {
            DeletedFileWarningBar(fileName: state.fileDisplayName, message: state.errorMessage)
                .padding(.top, topPadding)
        } else if state.needsImageDirectoryAccess {
            ImageAccessWarningBar(onGrantAccess: onGrantImageAccess)
                .padding(.top, topPadding)
        }
    }
}
