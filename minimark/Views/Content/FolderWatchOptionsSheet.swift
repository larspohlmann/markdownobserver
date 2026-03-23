import Combine
import SwiftUI

struct FolderWatchOptionsSheet: View {
    let folderURL: URL?
    @Binding var openMode: ReaderFolderWatchOpenMode
    @Binding var scope: ReaderFolderWatchScope
    @Binding var excludedSubdirectoryPaths: [String]
    let onCancel: () -> Void
    let onConfirm: (ReaderFolderWatchOptions) -> Void

    @StateObject private var directoryScanModel = FolderWatchDirectoryScanModel()
    @State private var isLargeTreeDialogPresented = false
    @State private var expandedDirectoryPaths: Set<String> = []

    private enum Metrics {
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

    private var normalizedExcludedSubdirectoryPaths: [String] {
        guard let folderURL else {
            return []
        }

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let folderPathPrefix = normalizedFolderURL.path.hasSuffix("/") ? normalizedFolderURL.path : normalizedFolderURL.path + "/"

        let normalized = excludedSubdirectoryPaths.compactMap { path -> String? in
            guard !path.isEmpty else {
                return nil
            }

            let normalizedPath = ReaderFileRouting.normalizedFileURL(URL(fileURLWithPath: path, isDirectory: true)).path
            guard normalizedPath.hasPrefix(folderPathPrefix), normalizedPath != normalizedFolderURL.path else {
                return nil
            }

            return normalizedPath
        }

        return Array(Set(normalized)).sorted()
    }

    private var requiresExclusionSelectionBeforeStart: Bool {
        guard scope == .includeSubfolders,
              let summary = directoryScanModel.summary,
              summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold else {
            return false
        }

        return normalizedExcludedSubdirectoryPaths.isEmpty
    }

    private var thresholdWarningVisible: Bool {
        guard let summary = directoryScanModel.summary else {
            return false
        }

        return summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
    }

    private var scopeFooterText: String {
        guard scope == .includeSubfolders, folderURL != nil else {
            return "Enable subfolder watching to evaluate large-tree performance guidance."
        }

        if directoryScanModel.isLoading {
            return "Scanning subdirectories..."
        }

        if let summary = directoryScanModel.summary {
            let subdirectoryLabel = summary.subdirectoryCount == 1 ? "subdirectory" : "subdirectories"
            let markdownLabel = summary.markdownFileCount == 1 ? "Markdown file" : "Markdown files"

            if summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold {
                return "Large tree detected: \(summary.subdirectoryCount) \(subdirectoryLabel), \(summary.markdownFileCount) \(markdownLabel). Deactivate one or more subdirectories before starting watch."
            }

            return "Detected \(summary.subdirectoryCount) \(subdirectoryLabel) and \(summary.markdownFileCount) \(markdownLabel)."
        }

        return "Subdirectory metrics unavailable."
    }

    private var thresholdWarningTitle: String {
        guard let summary = directoryScanModel.summary else {
            return "Large tree optimization"
        }

        return "\(summary.subdirectoryCount) subdirectories detected"
    }

    private var thresholdWarningDetail: String {
        let selectedCount = normalizedExcludedSubdirectoryPaths.count
        if selectedCount > 0 {
            let noun = selectedCount == 1 ? "subdirectory" : "subdirectories"
            return "\(selectedCount) \(noun) currently deactivated. You can review and adjust selections before starting watch."
        }

        return "This exceeds the optimization threshold of \(ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold). Deactivate one or more subdirectories before starting to reduce freeze risk."
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

                    FolderWatchScopeSummaryView(
                        footerText: scopeFooterText,
                        isLoading: directoryScanModel.isLoading,
                        summary: directoryScanModel.summary,
                        canInspectLargeTree: thresholdWarningVisible,
                        onInspectLargeTree: {
                            isLargeTreeDialogPresented = true
                        }
                    )
                }

                if thresholdWarningVisible {
                    FolderWatchLargeTreeWarningCard(
                        title: thresholdWarningTitle,
                        detail: thresholdWarningDetail,
                        onInspect: {
                            isLargeTreeDialogPresented = true
                        }
                    )
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
                    confirmWithThresholdGuard()
                }
                .accessibilityIdentifier("folder-watch-start-button")
                .keyboardShortcut(.defaultAction)
                .disabled(folderURL == nil || directoryScanModel.isLoading)
                .accessibilityHint("Starts folder watch with selected options")
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-watch-sheet")
        .onAppear {
            refreshDirectoryScan()
        }
        .onChange(of: folderURL) { _, _ in
            refreshDirectoryScan()
        }
        .onChange(of: scope) { _, _ in
            refreshDirectoryScan()
        }
        .sheet(isPresented: $isLargeTreeDialogPresented) {
            LargeFolderExclusionDialog(
                threshold: ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold,
                scanModel: directoryScanModel,
                expandedDirectoryPaths: $expandedDirectoryPaths,
                excludedSubdirectoryPaths: Binding(
                    get: {
                        normalizedExcludedSubdirectoryPaths
                    },
                    set: { newValue in
                        excludedSubdirectoryPaths = newValue
                    }
                ),
                onCancel: {
                    isLargeTreeDialogPresented = false
                },
                onConfirm: {
                    guard !normalizedExcludedSubdirectoryPaths.isEmpty else {
                        return
                    }

                    isLargeTreeDialogPresented = false
                    confirmWithThresholdGuard()
                }
            )
        }
    }

    private func confirmWithThresholdGuard() {
        guard !requiresExclusionSelectionBeforeStart else {
            isLargeTreeDialogPresented = true
            return
        }

        onConfirm(
            ReaderFolderWatchOptions(
                openMode: openMode,
                scope: scope,
                excludedSubdirectoryPaths: normalizedExcludedSubdirectoryPaths
            )
        )
    }

    private func refreshDirectoryScan() {
        guard scope == .includeSubfolders,
              let folderURL else {
            directoryScanModel.reset()
            return
        }

        directoryScanModel.scan(folderURL: folderURL)
    }
}

private struct FolderWatchScopeSummaryView: View {
    let footerText: String
    let isLoading: Bool
    let summary: FolderWatchDirectoryScanSummary?
    let canInspectLargeTree: Bool
    let onInspectLargeTree: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label(
                    summary == nil ? "Subdirectories" : "\(summary?.subdirectoryCount ?? 0)",
                    systemImage: "folder.badge.gearshape"
                )
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

                Label(
                    summary == nil ? "Markdown files" : "\(summary?.markdownFileCount ?? 0)",
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(footerText)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if canInspectLargeTree {
                Button {
                    onInspectLargeTree()
                } label: {
                    Label("Review subdirectory exclusions", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.link)
            }
        }
        .padding(.top, 8)
    }
}

private struct FolderWatchLargeTreeWarningCard: View {
    let title: String
    let detail: String
    let onInspect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 17, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onInspect()
                } label: {
                    Label("Choose subdirectories to deactivate", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.yellow.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct LargeFolderExclusionDialog: View {
    let threshold: Int
    @ObservedObject var scanModel: FolderWatchDirectoryScanModel
    @Binding var expandedDirectoryPaths: Set<String>
    @Binding var excludedSubdirectoryPaths: [String]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var excludedSet: Set<String> {
        Set(excludedSubdirectoryPaths)
    }

    private var canConfirm: Bool {
        !excludedSet.isEmpty
    }

    private var rootNodes: [FolderWatchDirectoryNode] {
        scanModel.rootNode?.children ?? []
    }

    private var allSubdirectoryPaths: [String] {
        rootNodes.flatMap { collectPaths(from: $0) }.sorted()
    }

    private var hasAnySubdirectory: Bool {
        !allSubdirectoryPaths.isEmpty
    }

    private var hasExcludedSubdirectories: Bool {
        !excludedSet.isEmpty
    }

    private var allSubdirectoriesExcluded: Bool {
        hasAnySubdirectory && Set(allSubdirectoryPaths).isSubset(of: excludedSet)
    }

    private var effectivelyExcludedSubdirectoryCount: Int {
        allSubdirectoryPaths.filter(isPathEffectivelyExcluded).count
    }

    private var activeSubdirectoryCount: Int {
        max(0, allSubdirectoryPaths.count - effectivelyExcludedSubdirectoryCount)
    }

    private var remainingToDeactivateCount: Int {
        max(0, activeSubdirectoryCount - threshold)
    }

    private var thresholdProgressText: String {
        if remainingToDeactivateCount == 0 {
            return "Threshold satisfied. You can start watching now."
        }

        let noun = remainingToDeactivateCount == 1 ? "subdirectory" : "subdirectories"
        return "Deactivate \(remainingToDeactivateCount) more \(noun) to reach the threshold."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Optimize Large Folder Watch")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))

                    Text("This folder tree exceeds \(threshold) subdirectories. Deactivate one or more subdirectories to reduce scan pressure and avoid freezes.")
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if scanModel.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning subdirectories...")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                } else if let summary = scanModel.summary {
                    HStack(spacing: 14) {
                        Label("\(summary.subdirectoryCount) subdirectories", systemImage: "folder.fill.badge.plus")
                        Label("\(summary.markdownFileCount) Markdown files", systemImage: "doc.richtext")
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Label(
                            "\(activeSubdirectoryCount) active / \(effectivelyExcludedSubdirectoryCount) deactivated",
                            systemImage: "dial.medium"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                        Spacer()
                    }

                    Text(thresholdProgressText)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(remainingToDeactivateCount == 0 ? .green : .orange)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            excludedSubdirectoryPaths = allSubdirectoryPaths
                        } label: {
                            Label("Deactivate All", systemImage: "slash.circle")
                        }
                        .disabled(!hasAnySubdirectory || allSubdirectoriesExcluded)

                        Button {
                            excludedSubdirectoryPaths = []
                        } label: {
                            Label("Activate All", systemImage: "checkmark.circle")
                        }
                        .disabled(!hasExcludedSubdirectories)

                        Spacer()
                    }
                    .buttonStyle(.bordered)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
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
                    .frame(minHeight: 260)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                } else {
                    Text("Unable to scan this folder tree.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                }
            }

            HStack {
                let count = excludedSet.count
                let noun = count == 1 ? "subdirectory" : "subdirectories"
                Label("\(count) \(noun) deactivated", systemImage: count > 0 ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(count > 0 ? .green : .secondary)

                Text("Need \(remainingToDeactivateCount) more")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(remainingToDeactivateCount == 0 ? .green : .orange)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Start Watching") {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm || scanModel.isLoading)
            }
        }
        .padding(20)
        .frame(width: 700)
    }

    private func collectPaths(from node: FolderWatchDirectoryNode) -> [String] {
        [node.path] + node.children.flatMap { collectPaths(from: $0) }
    }

    private func isPathEffectivelyExcluded(_ path: String) -> Bool {
        excludedSet.contains { excludedPath in
            if excludedPath == path {
                return true
            }

            let prefix = excludedPath.hasSuffix("/") ? excludedPath : excludedPath + "/"
            return path.hasPrefix(prefix)
        }
    }
}

private struct FolderWatchTreeNodeRow: View {
    let node: FolderWatchDirectoryNode
    let level: Int
    @Binding var expandedDirectoryPaths: Set<String>
    @Binding var excludedSubdirectoryPaths: [String]

    private var excludedSet: Set<String> {
        Set(excludedSubdirectoryPaths)
    }

    private var isExplicitlyExcluded: Bool {
        excludedSet.contains(node.path)
    }

    private var isExcludedByAncestor: Bool {
        excludedSet.contains { excludedPath in
            guard excludedPath != node.path else {
                return false
            }

            let prefix = excludedPath.hasSuffix("/") ? excludedPath : excludedPath + "/"
            return node.path.hasPrefix(prefix)
        }
    }

    private var isEffectivelyExcluded: Bool {
        isExplicitlyExcluded || isExcludedByAncestor
    }

    private var canToggle: Bool {
        !isExcludedByAncestor
    }

    private var hasChildren: Bool {
        !node.children.isEmpty
    }

    private var isExpanded: Bool {
        expandedDirectoryPaths.contains(node.path)
    }

    private var statusTitle: String {
        isEffectivelyExcluded ? "Deactivated" : "Active"
    }

    private var statusSymbol: String {
        isEffectivelyExcluded ? "slash.circle.fill" : "checkmark.circle.fill"
    }

    private var statusHint: String {
        if isExcludedByAncestor {
            return "Inherited from parent"
        }

        return isEffectivelyExcluded ? "Click to activate" : "Click to deactivate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleExpanded()
                } label: {
                    Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "circle.fill")
                        .font(.system(size: hasChildren ? 11 : 4, weight: .bold))
                        .foregroundStyle(hasChildren ? .secondary : .tertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)

                Image(systemName: isEffectivelyExcluded ? "folder.slash.fill" : "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEffectivelyExcluded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(node.subdirectoryCount)", systemImage: "folder")
                        Label("\(node.markdownFileCount)", systemImage: "doc.text")
                    }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    toggleExclusion()
                } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        Label(statusTitle, systemImage: statusSymbol)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(
                                isEffectivelyExcluded
                                    ? AnyShapeStyle(.secondary)
                                    : AnyShapeStyle(Color.green)
                            )

                        Text(statusHint)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canToggle ? Color.primary.opacity(0.06) : Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.borderless)
                .disabled(!canToggle)
                .accessibilityHint(statusHint)
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEffectivelyExcluded ? Color.secondary.opacity(0.08) : Color.clear)
            )

            if hasChildren && isExpanded {
                ForEach(node.children) { child in
                    FolderWatchTreeNodeRow(
                        node: child,
                        level: level + 1,
                        expandedDirectoryPaths: $expandedDirectoryPaths,
                        excludedSubdirectoryPaths: $excludedSubdirectoryPaths
                    )
                }
            }
        }
    }

    private func toggleExpanded() {
        guard hasChildren else {
            return
        }

        if isExpanded {
            expandedDirectoryPaths.remove(node.path)
        } else {
            expandedDirectoryPaths.insert(node.path)
        }
    }

    private func toggleExclusion() {
        guard canToggle else {
            return
        }

        var next = Set(excludedSubdirectoryPaths)
        if isExplicitlyExcluded {
            next.remove(node.path)
        } else {
            let prefix = node.path.hasSuffix("/") ? node.path : node.path + "/"
            next = next.filter { !$0.hasPrefix(prefix) }
            next.insert(node.path)
        }

        excludedSubdirectoryPaths = Array(next).sorted()
    }
}

private struct FolderWatchDirectoryScanSummary: Equatable {
    let subdirectoryCount: Int
    let markdownFileCount: Int
}

private struct FolderWatchDirectoryNode: Identifiable, Equatable {
    let path: String
    let name: String
    var children: [FolderWatchDirectoryNode]
    var subdirectoryCount: Int
    var markdownFileCount: Int

    var id: String { path }
}

private final class FolderWatchDirectoryScanModel: ObservableObject {
    nonisolated private enum ScanLimit {
        static let maximumTraversalDepth = 48
        static let maximumVisitedDirectories = 20_000
    }

    @Published private(set) var isLoading = false
    @Published private(set) var rootNode: FolderWatchDirectoryNode?
    @Published private(set) var summary: FolderWatchDirectoryScanSummary?

    private var activeTask: Task<Void, Never>?

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        rootNode = nil
        summary = nil
    }

    func scan(folderURL: URL) {
        activeTask?.cancel()
        isLoading = true
        rootNode = nil
        summary = nil

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        activeTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.buildTree(at: normalizedFolderURL)
            }.value

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                isLoading = false
                rootNode = result

                if let result {
                    summary = FolderWatchDirectoryScanSummary(
                        subdirectoryCount: result.subdirectoryCount,
                        markdownFileCount: result.markdownFileCount
                    )
                }
            }
        }
    }

    nonisolated private static func buildTree(at folderURL: URL) -> FolderWatchDirectoryNode? {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard (try? normalizedFolderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }

        var visitedDirectoryPaths = Set<String>()
        return buildNode(
            at: normalizedFolderURL,
            depth: 0,
            visitedDirectoryPaths: &visitedDirectoryPaths
        )
    }

    nonisolated private static func buildNode(
        at directoryURL: URL,
        depth: Int,
        visitedDirectoryPaths: inout Set<String>
    ) -> FolderWatchDirectoryNode? {
        guard depth <= ScanLimit.maximumTraversalDepth else {
            return nil
        }

        let normalizedDirectoryURL = ReaderFileRouting.normalizedFileURL(directoryURL)
        let normalizedDirectoryPath = normalizedDirectoryURL.path

        guard visitedDirectoryPaths.count < ScanLimit.maximumVisitedDirectories else {
            return nil
        }

        guard visitedDirectoryPaths.insert(normalizedDirectoryPath).inserted else {
            return nil
        }

        let fileManager = FileManager.default

        guard let entries = try? fileManager.contentsOfDirectory(
            at: normalizedDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return nil
        }

        var childDirectories: [FolderWatchDirectoryNode] = []
        var markdownCount = 0

        for entry in entries {
            let normalizedEntry = ReaderFileRouting.normalizedFileURL(entry)
            let values = try? normalizedEntry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])

            if values?.isSymbolicLink == true {
                continue
            }

            if values?.isDirectory == true {
                if let childNode = buildNode(
                    at: normalizedEntry,
                    depth: depth + 1,
                    visitedDirectoryPaths: &visitedDirectoryPaths
                ) {
                    childDirectories.append(childNode)
                    markdownCount += childNode.markdownFileCount
                }
                continue
            }

            if values?.isRegularFile == true,
               ReaderFileRouting.isSupportedMarkdownFileURL(normalizedEntry) {
                markdownCount += 1
            }
        }

        childDirectories.sort(by: { $0.path < $1.path })
        let descendantSubdirectoryCount = childDirectories.reduce(0) { $0 + 1 + $1.subdirectoryCount }
        let name = normalizedDirectoryURL.lastPathComponent.isEmpty ? normalizedDirectoryURL.path : normalizedDirectoryURL.lastPathComponent

        return FolderWatchDirectoryNode(
            path: normalizedDirectoryURL.path,
            name: name,
            children: childDirectories,
            subdirectoryCount: descendantSubdirectoryCount,
            markdownFileCount: markdownCount
        )
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
