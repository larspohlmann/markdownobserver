import SwiftUI

struct EditFolderWatchSheet: View {
    let folderURL: URL
    let currentExcludedSubdirectoryPaths: [String]
    let onConfirm: ([String]) -> Void
    let onCancel: () -> Void

    @StateObject private var scanModel = FolderWatchDirectoryScanModel()
    @State private var excludedSubdirectoryPaths: [String]
    @State private var expandedDirectoryPaths: Set<String> = []

    init(
        folderURL: URL,
        currentExcludedSubdirectoryPaths: [String],
        onConfirm: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.folderURL = folderURL
        self.currentExcludedSubdirectoryPaths = currentExcludedSubdirectoryPaths
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._excludedSubdirectoryPaths = State(initialValue: currentExcludedSubdirectoryPaths)
    }

    private var rootNodes: [FolderWatchDirectoryNode] {
        scanModel.rootNode?.children ?? []
    }

    private var activeSubdirectoryCount: Int {
        let totalCount = scanModel.allSubdirectoryPaths.count
        let excludedSet = Set(excludedSubdirectoryPaths)
        let excludedCount = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: scanModel.allSubdirectoryPaths,
            excludedPaths: excludedSet
        )
        return totalCount - excludedCount
    }

    private var excludedSubdirectoryCount: Int {
        let excludedSet = Set(excludedSubdirectoryPaths)
        return FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: scanModel.allSubdirectoryPaths,
            excludedPaths: excludedSet
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Subfolders")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)

                    Text(abbreviatePathWithTilde(folderURL.path))
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Button {
                            excludedSubdirectoryPaths = scanModel.allSubdirectoryPaths
                        } label: {
                            Label("Deactivate All", systemImage: "slash.circle")
                        }
                        .disabled(scanModel.allSubdirectoryPaths.isEmpty)

                        Button {
                            excludedSubdirectoryPaths = []
                        } label: {
                            Label("Activate All", systemImage: "checkmark.circle")
                        }
                        .disabled(excludedSubdirectoryPaths.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text("\(activeSubdirectoryCount) active")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    if excludedSubdirectoryCount > 0 {
                        Text("\(excludedSubdirectoryCount) excluded")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if scanModel.isLoading {
                VStack(spacing: 10) {
                    if let progress = scanModel.scanProgress {
                        ProgressView(value: progress.fractionCompleted)
                            .progressViewStyle(.linear)
                            .frame(width: 320)
                            .controlSize(.small)

                        Text("Scanning subdirectories... \(progress.scannedDirectoryCount) folders processed")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning subdirectories...")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            } else if scanModel.summary != nil {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rootNodes) { node in
                            FolderWatchTreeNodeRow(
                                node: node,
                                level: 0,
                                expandedDirectoryPaths: $expandedDirectoryPaths,
                                excludedSubdirectoryPaths: $excludedSubdirectoryPaths
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                Text("Unable to scan this folder tree.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    onConfirm(excludedSubdirectoryPaths)
                }
                .buttonStyle(FolderWatchPrimaryActionButtonStyle(tint: .accentColor))
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(scanModel.isLoading || scanModel.summary == nil)
            }
        }
        .padding(22)
        .frame(width: 620)
        .onAppear {
            scanModel.scan(folderURL: folderURL)
        }
    }
}
