import SwiftUI

struct FolderWatchOptionsSheet: View {
    let folderURL: URL?
    @Binding var openMode: ReaderFolderWatchOpenMode
    @Binding var scope: ReaderFolderWatchScope
    let onCancel: () -> Void
    let onConfirm: (ReaderFolderWatchOptions) -> Void

    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let innerCornerRadius: CGFloat = 12
        static let sectionSpacing: CGFloat = 14
        static let contentSpacing: CGFloat = 18
        static let width: CGFloat = 520
    }

    private var selectedFolderName: String {
        guard let folderURL else {
            return "No folder selected"
        }

        return folderURL.lastPathComponent
    }

    private var selectedFolderPath: String {
        folderURL?.path ?? "Choose a folder to configure watch behavior."
    }

    private var selectionSummary: String {
        switch openMode {
        case .openAllMarkdownFiles:
            switch scope {
            case .selectedFolderOnly:
                return "Will automatically open up to \(ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount) Markdown files in the selected folder, then continue watching that folder."
            case .includeSubfolders:
                return "Will automatically open up to \(ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount) Markdown files across the folder tree, then continue watching subfolders."
            }
        case .watchChangesOnly:
            switch scope {
            case .selectedFolderOnly:
                return "Will monitor the selected folder and open Markdown files only when changes arrive."
            case .includeSubfolders:
                return "Will monitor the full folder tree and open Markdown files only when changes arrive."
            }
        }
    }

    private var selectionStateKey: String {
        "\(openMode.rawValue)|\(scope.rawValue)"
    }

    private var openAllMarkdownFilesBinding: Binding<Bool> {
        Binding(
            get: {
                openMode == .openAllMarkdownFiles
            },
            set: { isEnabled in
                openMode = isEnabled ? .openAllMarkdownFiles : .watchChangesOnly
            }
        )
    }

    private var includeSubfoldersBinding: Binding<Bool> {
        Binding(
            get: {
                scope == .includeSubfolders
            },
            set: { isEnabled in
                scope = isEnabled ? .includeSubfolders : .selectedFolderOnly
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
            FolderWatchHeaderView()

            FolderWatchSummaryCard(
                folderName: selectedFolderName,
                folderPath: selectedFolderPath,
                summary: selectionSummary,
                hasFolderSelection: folderURL != nil,
                selectionStateKey: selectionStateKey
            )

            VStack(spacing: Metrics.sectionSpacing) {
                FolderWatchOptionSection(
                    title: "When watch starts",
                    description: "Choose whether MarkdownObserver should immediately open existing Markdown files or wait for incoming changes."
                ) {
                    Toggle("Open all Markdown files", isOn: openAllMarkdownFilesBinding)
                        .accessibilityLabel("Open all Markdown files")
                }

                FolderWatchOptionSection(
                    title: "Folder scope",
                    description: "Control whether watch activity stays in the selected folder or also follows subfolders."
                ) {
                    Toggle("Include subfolders", isOn: includeSubfoldersBinding)
                        .accessibilityLabel("Include subfolders")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .accessibilityIdentifier("folder-watch-cancel-button")
                .keyboardShortcut(.cancelAction)

                Button("Start Watching") {
                    onConfirm(
                        ReaderFolderWatchOptions(
                            openMode: openMode,
                            scope: scope
                        )
                    )
                }
                .accessibilityIdentifier("folder-watch-start-button")
                .keyboardShortcut(.defaultAction)
                .disabled(folderURL == nil)
                .accessibilityHint("Starts folder watch with selected options")
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-watch-sheet")
    }
}

private struct FolderWatchHeaderView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "binoculars.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Watch Folder")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)

                Text("Monitor a folder for Markdown activity and decide how MarkdownObserver should respond when watch begins.")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FolderWatchSummaryCard: View {
    let folderName: String
    let folderPath: String
    let summary: String
    let hasFolderSelection: Bool
    let selectionStateKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: hasFolderSelection ? "folder.fill" : "folder.badge.questionmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(hasFolderSelection ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.07))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(hasFolderSelection ? "Selected folder" : "Folder required")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(folderName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hasFolderSelection ? .primary : .secondary)
                        .lineLimit(1)

                    Text(folderPath)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .accessibilityLabel("Folder path")
                        .accessibilityValue(folderPath)
                }
            }

            Text(summary)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
                .accessibilityLabel("Watch summary")
                .accessibilityValue(summary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityIdentifier("folder-watch-summary-card")
        .accessibilityValue(selectionStateKey)
    }
}

private struct FolderWatchOptionSection<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}