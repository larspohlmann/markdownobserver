import SwiftUI

struct FolderWatchFileSelectionSheet: View {
    @ObservedObject var model: FolderWatchFileSelectionModel
    let onSkip: () -> Void
    let onConfirm: ([URL]) -> Void

    @State private var expandedDirectoryPaths: Set<String> = []

    private enum Metrics {
        static let width: CGFloat = 580
        static let listHeight: CGFloat = 320
    }

    private var selectedCountText: String {
        "\(model.selectedCount) selected"
    }

    private var openButtonTitle: String {
        let count = model.selectedCount
        return count == 1 ? "Open 1 File" : "Open \(count) Files"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: Header
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose Files to Open")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))

                    Text("\(model.totalCount) Markdown files found in this folder.")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // MARK: Folder path
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(model.folderURL.path)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            // MARK: File tree
            VStack(spacing: 0) {
                // Toolbar
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Button("Select All") {
                            model.selectAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.selectedCount == model.totalCount)

                        Button("Clear All") {
                            model.clearAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.selectedCount == 0)
                    }

                    Spacer()

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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                // Tree list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.rootNodes) { node in
                            FileSelectionTreeNodeRow(
                                node: node,
                                level: 0,
                                model: model,
                                expandedDirectoryPaths: $expandedDirectoryPaths
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: Metrics.listHeight)
                .background(Color(nsColor: .controlBackgroundColor))
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            )

            // MARK: Performance warning
            if model.exceedsPerformanceThreshold {
                FolderWatchLargeTreeWarningCard(
                    title: "\(model.selectedCount) files selected",
                    detail: "Opening more than \(ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount) files at once may slow down the system. Consider selecting fewer files.",
                    tone: .warning,
                    showsAction: false,
                    onInspect: {}
                )
            }

            Divider()

            // MARK: Actions
            HStack {
                Text(model.selectedCount == 0
                     ? "Select files to open, or skip to watch only."
                     : "Folder watching continues regardless of selection.")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(openButtonTitle) {
                    onConfirm(Array(model.selectedFileURLs))
                }
                .buttonStyle(FolderWatchPrimaryActionButtonStyle(tint: .accentColor))
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedCount == 0)
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
    }
}

private struct FileSelectionTreeNodeRow: View {
    let node: FileSelectionNode
    let level: Int
    @ObservedObject var model: FolderWatchFileSelectionModel
    @Binding var expandedDirectoryPaths: Set<String>

    private var isExpanded: Bool {
        expandedDirectoryPaths.contains(node.path)
    }

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    var body: some View {
        if node.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    @ViewBuilder
    private var directoryRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "circle.fill")
                        .font(.system(size: hasChildren ? 10 : 4, weight: .bold))
                        .foregroundStyle(hasChildren ? .secondary : .tertiary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)

                Image(systemName: "folder.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                Text(node.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text("\(node.markdownFileCount) \(node.markdownFileCount == 1 ? "file" : "files")")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                folderToggle
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.clear)
            )

            if hasChildren && isExpanded {
                ForEach(node.children) { child in
                    FileSelectionTreeNodeRow(
                        node: child,
                        level: level + 1,
                        model: model,
                        expandedDirectoryPaths: $expandedDirectoryPaths
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var folderToggle: some View {
        let isFullySelected = model.isNodeFullySelected(node)
        let isPartiallySelected = model.isNodePartiallySelected(node)

        Button {
            model.toggleFolder(node)
        } label: {
            Image(systemName: isFullySelected
                  ? "checkmark.circle.fill"
                  : isPartiallySelected
                  ? "minus.circle.fill"
                  : "circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isFullySelected
                                ? Color.accentColor
                                : isPartiallySelected
                                ? Color.accentColor.opacity(0.6)
                                : .secondary)
        }
        .buttonStyle(.plain)
        .help("Toggle all files in this folder")
    }

    @ViewBuilder
    private var fileRow: some View {
        let isSelected = node.fileURL.map { model.isSelected($0) } ?? false

        HStack(spacing: 8) {
            // Spacer to align with disclosure triangle
            Color.clear
                .frame(width: 14, height: 14)

            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Text(node.name)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in
                    if let fileURL = node.fileURL {
                        model.toggleFile(fileURL)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(Text(node.name))
        }
        .padding(.leading, CGFloat(level) * 16)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .opacity(isSelected ? 1.0 : 0.65)
    }

    private func toggleExpanded() {
        if expandedDirectoryPaths.contains(node.path) {
            expandedDirectoryPaths.remove(node.path)
        } else {
            expandedDirectoryPaths.insert(node.path)
        }
    }
}
