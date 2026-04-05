import SwiftUI

struct SidebarScanProgressView: View {
    @ObservedObject var controller: ReaderSidebarDocumentController

    var body: some View {
        if let session = controller.activeFolderWatchSession {
            VStack(spacing: 0) {
                Divider()
                footerContent(session: session)
            }
            .background(.bar)
        }
    }

    private func footerContent(session: ReaderFolderWatchSession) -> some View {
        HStack(spacing: 6) {
            if let progress = controller.contentScanProgress, !progress.isFinished {
                ProgressView(value: Double(progress.completed), total: max(Double(progress.total), 1))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 60)

                Text("Scanning \(progress.completed)/\(progress.total) files")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                if let fileCount = controller.scannedFileCount, fileCount > 0 {
                    Text("\(fileCount) \(fileCount == 1 ? "file" : "files")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(session.detailSummaryTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.3), value: controller.contentScanProgress?.isFinished)
    }
}
