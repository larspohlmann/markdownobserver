import Combine
import SwiftUI

@MainActor
final class FolderWatchAutoOpenSelectionModel: ObservableObject {
    let omittedFileURLs: [URL]
    @Published var selectedFileURLs: Set<URL>

    init(omittedFileURLs: [URL]) {
        self.omittedFileURLs = omittedFileURLs
        self.selectedFileURLs = []
    }

    func isSelected(_ fileURL: URL) -> Bool {
        selectedFileURLs.contains(fileURL)
    }

    func setSelected(_ isSelected: Bool, for fileURL: URL) {
        if isSelected {
            selectedFileURLs.insert(fileURL)
        } else {
            selectedFileURLs.remove(fileURL)
        }
    }

    func selectAll() {
        selectedFileURLs = Set(omittedFileURLs)
    }

    func clearSelection() {
        selectedFileURLs.removeAll()
    }
}

@MainActor
final class FolderWatchAutoOpenWarningFlow: ObservableObject, Identifiable {
    enum Step {
        case warning
        case selection
    }

    let id = UUID()
    let warning: ReaderFolderWatchAutoOpenWarning
    let selectionModel: FolderWatchAutoOpenSelectionModel
    @Published var step: Step

    private var selectionChangeObserver: AnyCancellable?

    init(warning: ReaderFolderWatchAutoOpenWarning) {
        self.warning = warning
        self.selectionModel = FolderWatchAutoOpenSelectionModel(omittedFileURLs: warning.omittedFileURLs)
        self.step = .warning
        self.selectionChangeObserver = selectionModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func showSelectionStep() {
        step = .selection
    }

    func showWarningStep() {
        step = .warning
    }
}

struct FolderWatchAutoOpenWarningFlowSheet: View {
    @ObservedObject var flow: FolderWatchAutoOpenWarningFlow
    let onKeepCurrentFiles: () -> Void
    let onOpenSelectedFiles: () -> Void

    var body: some View {
        Group {
            switch flow.step {
            case .warning:
                FolderWatchAutoOpenWarningSheet(
                    warning: flow.warning,
                    onKeepCurrentFiles: onKeepCurrentFiles,
                    onSelectMoreFiles: {
                        flow.showSelectionStep()
                    }
                )

            case .selection:
                FolderWatchAutoOpenSelectionView(
                    folderURL: flow.warning.folderURL,
                    model: flow.selectionModel,
                    onBack: {
                        flow.showWarningStep()
                    },
                    onOpenSelectedFiles: onOpenSelectedFiles
                )
            }
        }
    }
}

private struct FolderWatchAutoOpenSelectionView: View {
    let folderURL: URL
    @ObservedObject var model: FolderWatchAutoOpenSelectionModel
    let onBack: () -> Void
    let onOpenSelectedFiles: () -> Void

    private enum Metrics {
        static let width: CGFloat = 540
        static let listHeight: CGFloat = 280
    }

    private var selectedCountText: String {
        let count = model.selectedFileURLs.count
        return count == 1 ? "1 selected" : "\(count) selected"
    }

    private var openButtonTitle: String {
        let count = model.selectedFileURLs.count
        return count == 1 ? "Open 1 Selected File" : "Open \(count) Selected Files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose Additional Files")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Only the files you select here will be opened now. Folder watching continues either way.")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(selectedCountText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Watched folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(folderURL.path)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available Files")
                            .font(.system(size: 12, weight: .semibold))
                        Text("These Markdown files were skipped during automatic opening.")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Select All") {
                        model.selectAll()
                    }
                    .buttonStyle(.link)

                    Button("Clear") {
                        model.clearSelection()
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.omittedFileURLs, id: \.self) { fileURL in
                            Toggle(isOn: Binding(
                                get: {
                                    model.isSelected(fileURL)
                                },
                                set: { isSelected in
                                    model.setSelected(isSelected, for: fileURL)
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(fileURL.lastPathComponent)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(relativeDisplayPath(for: fileURL))
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.vertical, 4)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(14)
                }
                .frame(height: Metrics.listHeight)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )

            Divider()

            HStack(spacing: 12) {
                Text(model.selectedFileURLs.isEmpty ? "Select one or more files to open them now." : "Review your selection, then open the chosen files in the current workspace.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Back") {
                    onBack()
                }
                .keyboardShortcut(.cancelAction)

                Button(openButtonTitle) {
                    onOpenSelectedFiles()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedFileURLs.isEmpty)
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
    }

    private func relativeDisplayPath(for fileURL: URL) -> String {
        let normalizedFolderPath = folderURL.standardizedFileURL.path
        let normalizedFilePath = fileURL.standardizedFileURL.path

        guard normalizedFilePath.hasPrefix(normalizedFolderPath) else {
            return fileURL.path
        }

        let relativePath = String(normalizedFilePath.dropFirst(normalizedFolderPath.count))
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
}

private struct FolderWatchAutoOpenWarningSheet: View {
    let warning: ReaderFolderWatchAutoOpenWarning
    let onKeepCurrentFiles: () -> Void
    let onSelectMoreFiles: () -> Void

    private enum Metrics {
        static let width: CGFloat = 468
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.yellow.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Opened a limited set of Markdown files")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(
                        "MarkdownObserver opened \(warning.autoOpenedFileCount) of \(warning.totalFileCount) Markdown files automatically for this watched folder."
                    )
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Watched folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(warning.folderURL.path)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    statusBadge(title: "Opened \(warning.autoOpenedFileCount)")
                    statusBadge(title: "Skipped \(warning.omittedFileURLs.count)")
                }

                Text("Select more files manually if you want to open additional documents now. Watching continues either way.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )

            Divider()

            HStack {
                Spacer()
                Button("Keep Current Files") {
                    onKeepCurrentFiles()
                }
                .keyboardShortcut(.cancelAction)

                Button("Select More Files") {
                    onSelectMoreFiles()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
    }

    private func statusBadge(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
    }
}