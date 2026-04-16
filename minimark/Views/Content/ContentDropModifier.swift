import SwiftUI

struct ContentDropModifier: ViewModifier {
    let isBlockedFolderDropTargeted: Bool
    let isDragTargeted: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isBlockedFolderDropTargeted {
                FolderDropBlockedOverlayView()
                    .padding(10)
                    .allowsHitTesting(false)
            } else if isDragTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct FolderDropBlockedOverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.24))

            VStack(spacing: 6) {
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 22, weight: .semibold))

                Text("Already Watching a Folder")
                    .font(.headline)

                Text("Stop the current folder watch before dropping another folder.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .foregroundStyle(Color.black)
            .padding(20)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .systemYellow))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.orange, lineWidth: 2)
            )
        }
    }
}
