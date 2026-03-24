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
        static let contentSpacing: CGFloat = 16
        static let width: CGFloat = 560
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

    private var allScannedSubdirectoryPaths: [String] {
        directoryScanModel.allSubdirectoryPaths
    }

    private var effectiveExcludedSubdirectoryCount: Int {
        let excludedSet = Set(normalizedExcludedSubdirectoryPaths)
        return allScannedSubdirectoryPaths.filter { path in
            isPathEffectivelyExcluded(path, excludedSet: excludedSet)
        }.count
    }

    private var remainingSubdirectoriesToDeactivateCount: Int {
        guard let summary = directoryScanModel.summary else {
            return 0
        }

        let activeSubdirectoryCount = max(0, summary.subdirectoryCount - effectiveExcludedSubdirectoryCount)
        return max(0, activeSubdirectoryCount - ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold)
    }

    private var exceedsSupportedSubdirectoryLimit: Bool {
        scope == .includeSubfolders && directoryScanModel.didExceedSupportedSubdirectoryLimit
    }

    private var requiresHardLimitRefusal: Bool {
        exceedsSupportedSubdirectoryLimit
    }

    private var requiresExclusionSelectionBeforeStart: Bool {
        guard !requiresHardLimitRefusal else {
            return false
        }

        guard scope == .includeSubfolders,
              let summary = directoryScanModel.summary,
              summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold else {
            return false
        }

        return remainingSubdirectoriesToDeactivateCount > 0
    }

    private var thresholdWarningVisible: Bool {
        guard !requiresHardLimitRefusal else {
            return false
        }

        guard let summary = directoryScanModel.summary else {
            return false
        }

        return summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
    }

    private var scopeFooterText: String {
        guard scope == .includeSubfolders, folderURL != nil else {
            return "Enable subfolder watching to evaluate large-tree performance guidance."
        }

        let depthNote = "Include Subfolders scans up to \(ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth) levels deep."

        if directoryScanModel.isLoading {
            if let progress = directoryScanModel.scanProgress {
                return "Scanning subdirectories... \(progress.scannedDirectoryCount) folders processed. \(depthNote)"
            }
            return "Scanning subdirectories... \(depthNote)"
        }

        if requiresHardLimitRefusal {
            return "This folder has more than \(ReaderFolderWatchPerformancePolicy.maximumSupportedSubdirectoryCount) subdirectories. Include Subfolders is unavailable for this folder. \(depthNote)"
        }

        if let summary = directoryScanModel.summary {
            let subdirectoryLabel = summary.subdirectoryCount == 1 ? "subdirectory" : "subdirectories"
            let markdownLabel = summary.markdownFileCount == 1 ? "Markdown file" : "Markdown files"

            if summary.subdirectoryCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold {
                return "Large tree detected: \(summary.subdirectoryCount) \(subdirectoryLabel), \(summary.markdownFileCount) \(markdownLabel). Deactivate one or more subdirectories before starting watch. \(depthNote)"
            }

            return "Detected \(summary.subdirectoryCount) \(subdirectoryLabel) and \(summary.markdownFileCount) \(markdownLabel). \(depthNote)"
        }

        return "Subdirectory metrics unavailable. \(depthNote)"
    }

    private var thresholdWarningTitle: String {
        guard let summary = directoryScanModel.summary else {
            return "Large tree optimization"
        }

        return "\(summary.subdirectoryCount) subdirectories detected"
    }

    private var thresholdWarningDetail: String {
        let selectedCount = normalizedExcludedSubdirectoryPaths.count
        if selectedCount > 0 && remainingSubdirectoriesToDeactivateCount == 0 {
            let noun = selectedCount == 1 ? "subdirectory" : "subdirectories"
            return "Threshold satisfied with \(selectedCount) \(noun) deactivated. You can start watching now."
        }

        if selectedCount > 0 {
            let noun = remainingSubdirectoriesToDeactivateCount == 1 ? "subdirectory" : "subdirectories"
            return "Deactivate \(remainingSubdirectoriesToDeactivateCount) more \(noun) to reach the optimization threshold."
        }

        return "This exceeds the optimization threshold of \(ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold). Deactivate one or more subdirectories before starting to reduce freeze risk."
    }

    private var optimizationCardTitle: String {
        guard scope == .includeSubfolders else {
            return "Subfolder optimization"
        }

        guard !directoryScanModel.isLoading else {
            return "Scanning subfolders"
        }

        if requiresHardLimitRefusal {
            return "Folder too large for Include Subfolders"
        }

        return thresholdWarningVisible
            ? thresholdWarningTitle
            : "Tree size is within optimization threshold"
    }

    private var optimizationCardDetail: String {
        guard scope == .includeSubfolders else {
            return "Enable Include Subfolders to evaluate tree size and optimization guidance."
        }

        guard !directoryScanModel.isLoading else {
            return "Collecting subfolder metrics to evaluate large-tree performance."
        }

        if requiresHardLimitRefusal {
            return "Detected more than \(ReaderFolderWatchPerformancePolicy.maximumSupportedSubdirectoryCount) subdirectories. To avoid long freezes, this configuration cannot be started. Choose Selected Folder instead."
        }

        return thresholdWarningVisible
            ? thresholdWarningDetail
            : "No exclusions required. You can start watching with subfolders enabled."
    }

    private var optimizationCardTone: FolderWatchLargeTreeWarningCard.Tone {
        guard scope == .includeSubfolders else {
            return .neutral
        }

        guard !directoryScanModel.isLoading else {
            return .neutral
        }

        if requiresHardLimitRefusal {
            return .warning
        }

        return thresholdWarningVisible ? .warning : .success
    }

    private var startActionStatusText: String {
        if requiresHardLimitRefusal {
            return "Include Subfolders unavailable"
        }

        if requiresExclusionSelectionBeforeStart {
            return "Action required before watch can start"
        }

        return thresholdWarningVisible
            ? "Large tree reviewed"
            : "Ready to start"
    }

    private var startActionStatusSymbol: String {
        if requiresHardLimitRefusal {
            return "xmark.octagon.fill"
        }

        if requiresExclusionSelectionBeforeStart {
            return "exclamationmark.triangle.fill"
        }

        return thresholdWarningVisible ? "checkmark.shield.fill" : "checkmark.circle.fill"
    }

    private var startActionStatusColor: AnyShapeStyle {
        if requiresHardLimitRefusal {
            return AnyShapeStyle(.red)
        }

        if requiresExclusionSelectionBeforeStart {
            return AnyShapeStyle(.orange)
        }

        return AnyShapeStyle(.green)
    }

    private var openModeSelectionBinding: Binding<ReaderFolderWatchOpenMode> {
        Binding(
            get: {
                openMode
            },
            set: { mode in
                openMode = mode
            }
        )
    }

    private var scopeSelectionBinding: Binding<ReaderFolderWatchScope> {
        Binding(
            get: {
                scope
            },
            set: { updatedScope in
                guard scope != updatedScope else {
                    return
                }

                // Avoid mutating view state during the segmented control's active AppKit layout pass.
                DispatchQueue.main.async {
                    scope = updatedScope
                }
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
                openModeLabel: openMode == .openAllMarkdownFiles ? "Open Existing Files" : "Watch Changes Only",
                scopeLabel: scope == .includeSubfolders ? "Include Subfolders" : "Selected Folder Only",
                hasFolderSelection: folderURL != nil,
                selectionStateKey: selectionStateKey
            )

            VStack(spacing: Metrics.sectionSpacing) {
                FolderWatchOptionSection(
                    title: "When watch starts",
                    description: "Choose whether MarkdownObserver opens existing Markdown files immediately or waits for incoming changes."
                ) {
                    Picker("Watch start mode", selection: openModeSelectionBinding) {
                        Text("Open Existing Files")
                            .tag(ReaderFolderWatchOpenMode.openAllMarkdownFiles)
                        Text("Watch Changes Only")
                            .tag(ReaderFolderWatchOpenMode.watchChangesOnly)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Watch start mode")
                }

                FolderWatchOptionSection(
                    title: "Folder scope",
                    description: "Control whether watch activity stays in the selected folder or follows subfolders."
                ) {
                    Picker("Folder scope", selection: scopeSelectionBinding) {
                        Text("Selected Folder")
                            .tag(ReaderFolderWatchScope.selectedFolderOnly)
                        Text("Include Subfolders")
                            .tag(ReaderFolderWatchScope.includeSubfolders)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Folder scope")

                    FolderWatchScopeSummaryView(
                        footerText: scopeFooterText,
                        isLoading: directoryScanModel.isLoading,
                        scanProgress: directoryScanModel.scanProgress,
                        summary: directoryScanModel.summary
                    )
                }

                FolderWatchLargeTreeWarningCard(
                    title: optimizationCardTitle,
                    detail: optimizationCardDetail,
                    tone: optimizationCardTone,
                    showsAction: thresholdWarningVisible && !requiresHardLimitRefusal,
                    onInspect: {
                        isLargeTreeDialogPresented = true
                    }
                )
            }
            .transaction { transaction in
                transaction.animation = nil
            }

            Divider()

            HStack {
                Label(startActionStatusText, systemImage: startActionStatusSymbol)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(startActionStatusColor)

                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .accessibilityIdentifier("folder-watch-cancel-button")
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    confirmWithThresholdGuard()
                } label: {
                    if requiresExclusionSelectionBeforeStart {
                        Label("Start Watching", systemImage: "lock.fill")
                    } else {
                        Text("Start Watching")
                    }
                }
                .accessibilityIdentifier("folder-watch-start-button")
                .buttonStyle(FolderWatchPrimaryActionButtonStyle(tint: .accentColor))
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(folderURL == nil || directoryScanModel.isLoading || requiresExclusionSelectionBeforeStart || requiresHardLimitRefusal)
                .accessibilityHint("Starts folder watch with selected options")
            }
        }
        .padding(24)
        .frame(width: Metrics.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folder-watch-sheet")
        .onAppear {
            scheduleDirectoryScanRefresh()
        }
        .onChange(of: folderURL) { _, _ in
            scheduleDirectoryScanRefresh()
        }
        .onChange(of: scope) { _, _ in
            scheduleDirectoryScanRefresh()
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
                    isLargeTreeDialogPresented = false
                    confirmWithThresholdGuard()
                }
            )
        }
    }

    private func confirmWithThresholdGuard() {
        guard !requiresHardLimitRefusal else {
            return
        }

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

    private func scheduleDirectoryScanRefresh() {
        // Defer state mutation to avoid re-entrant AppKit layout while segmented control changes.
        DispatchQueue.main.async {
            refreshDirectoryScan()
        }
    }

    private func isPathEffectivelyExcluded(_ path: String, excludedSet: Set<String>) -> Bool {
        excludedSet.contains { excludedPath in
            if excludedPath == path {
                return true
            }

            let prefix = excludedPath.hasSuffix("/") ? excludedPath : excludedPath + "/"
            return path.hasPrefix(prefix)
        }
    }
}

private struct FolderWatchScopeSummaryView: View {
    let footerText: String
    let isLoading: Bool
    let scanProgress: FolderWatchDirectoryScanProgress?
    let summary: FolderWatchDirectoryScanSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                FolderWatchMetricPill(
                    title: summary == nil ? "Subdirectories" : "\(summary?.subdirectoryCount ?? 0)",
                    symbol: "folder.badge.gearshape"
                )

                FolderWatchMetricPill(
                    title: summary == nil ? "Markdown files" : "\(summary?.markdownFileCount ?? 0)",
                    symbol: "doc.text.magnifyingglass"
                )

                Spacer()

                if isLoading {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let scanProgress {
                            Text("\(scanProgress.scannedDirectoryCount) scanned")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            ProgressView(value: scanProgress.fractionCompleted)
                                .progressViewStyle(.linear)
                                .frame(width: 120)
                                .controlSize(.small)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            }

            Text(footerText)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

private struct FolderWatchMetricPill: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

private struct FolderWatchPrimaryActionButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled

    private var textStyle: AnyShapeStyle {
        isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.46))
    }

    private var fillColor: Color {
        isEnabled ? tint : Color.secondary.opacity(0.16)
    }

    private var borderColor: Color {
        isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(textStyle)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fillColor.opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1.0) : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .opacity(isEnabled ? 1.0 : 0.62)
    }
}

private struct FolderWatchSecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(
                isEnabled
                    ? AnyShapeStyle(.primary)
                    : AnyShapeStyle(.secondary.opacity(0.85))
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isEnabled
                            ? Color.primary.opacity(configuration.isPressed ? 0.14 : 0.10)
                            : Color.primary.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
            )
    }
}

private struct FolderWatchLargeTreeWarningCard: View {
    enum Tone {
        case neutral
        case success
        case warning
    }

    let title: String
    let detail: String
    let tone: Tone
    let showsAction: Bool
    let onInspect: () -> Void

    private var symbolName: String {
        switch tone {
        case .neutral:
            return "info.circle.fill"
        case .success:
            return "checkmark.seal.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tintColor: Color {
        switch tone {
        case .neutral:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbolName)
                    .foregroundStyle(tintColor)
                    .font(.system(size: 16, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showsAction {
                    Button {
                        onInspect()
                    } label: {
                        Label("Choose subdirectories to deactivate", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tintColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tintColor.opacity(0.35), lineWidth: 1)
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

    @State private var preparedSubdirectoryPaths: [String] = []
    @State private var effectiveExcludedSubdirectoryCount = 0
    @State private var effectiveExcludedCountTask: Task<Void, Never>?
    @State private var didNormalizeInitialExclusionSelection = false

    private var excludedSet: Set<String> {
        Set(excludedSubdirectoryPaths)
    }

    private var canConfirm: Bool {
        remainingToDeactivateCount == 0
    }

    private var rootNodes: [FolderWatchDirectoryNode] {
        scanModel.rootNode?.children ?? []
    }

    private var hasAnySubdirectory: Bool {
        !preparedSubdirectoryPaths.isEmpty
    }

    private var hasExcludedSubdirectories: Bool {
        !excludedSet.isEmpty
    }

    private var allSubdirectoriesExcluded: Bool {
        hasAnySubdirectory && Set(preparedSubdirectoryPaths).isSubset(of: excludedSet)
    }

    private var activeSubdirectoryCount: Int {
        max(0, preparedSubdirectoryPaths.count - effectiveExcludedSubdirectoryCount)
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

    private var thresholdProgressSymbol: String {
        remainingToDeactivateCount == 0 ? "checkmark.seal.fill" : "exclamationmark.circle.fill"
    }

    private var thresholdProgressStyle: AnyShapeStyle {
        remainingToDeactivateCount == 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.orange)
    }

    private var confirmButtonTitle: String {
        "Start Watching"
    }

    private var footerNeedText: String {
        if remainingToDeactivateCount == 0 {
            return "Threshold met"
        }

        return "Need \(remainingToDeactivateCount) more"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
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

                        Label("Depth limit: \(ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth) levels", systemImage: "arrow.down.to.line.compact")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.16))
                            )

                        Text("This folder tree exceeds \(threshold) subdirectories. Deactivate one or more subdirectories to reduce scan pressure and avoid freezes.")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    FolderWatchMetricPill(
                        title: "Threshold \(threshold)",
                        symbol: "gauge.with.dots.needle.50percent"
                    )

                    FolderWatchMetricPill(
                        title: "\(excludedSet.count) manually deactivated",
                        symbol: "line.3.horizontal.decrease.circle"
                    )

                    Spacer()
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )

            Group {
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
                            "\(activeSubdirectoryCount) active / \(effectiveExcludedSubdirectoryCount) deactivated",
                            systemImage: "dial.medium"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Image(systemName: thresholdProgressSymbol)
                            .foregroundStyle(thresholdProgressStyle)

                        Text(thresholdProgressText)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(thresholdProgressStyle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                    HStack(spacing: 10) {
                        Button {
                            excludedSubdirectoryPaths = preparedSubdirectoryPaths
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
                        LazyVStack(alignment: .leading, spacing: 6) {
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

            Divider()

            HStack(spacing: 12) {
                let count = excludedSet.count
                let noun = count == 1 ? "subdirectory" : "subdirectories"
                Label("\(count) \(noun) deactivated", systemImage: count > 0 ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(count > 0 ? .green : .secondary)

                Text(footerNeedText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(remainingToDeactivateCount == 0 ? .green : .orange)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(confirmButtonTitle) {
                    onConfirm()
                }
                .accessibilityIdentifier("folder-watch-dialog-start-button")
                .buttonStyle(
                    FolderWatchPrimaryActionButtonStyle(
                        tint: remainingToDeactivateCount == 0 ? .accentColor : .orange
                    )
                )
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirm || scanModel.isLoading)
            }
        }
        .padding(22)
        .frame(width: 700)
        .onAppear {
            didNormalizeInitialExclusionSelection = false
            scheduleSubdirectoryPreparation()
        }
        .onDisappear {
            effectiveExcludedCountTask?.cancel()
            effectiveExcludedCountTask = nil
        }
        .onChange(of: scanModel.allSubdirectoryPaths) { _, _ in
            scheduleSubdirectoryPreparation()
        }
        .onChange(of: preparedSubdirectoryPaths) { _, _ in
            normalizeInitialExclusionSelectionIfNeeded()
            scheduleEffectiveExcludedCountRefresh()
        }
        .onChange(of: excludedSubdirectoryPaths) { _, _ in
            scheduleEffectiveExcludedCountRefresh()
        }
    }

    private func scheduleSubdirectoryPreparation() {
        guard !scanModel.isLoading else {
            preparedSubdirectoryPaths = []
            effectiveExcludedSubdirectoryCount = 0
            return
        }

        preparedSubdirectoryPaths = scanModel.allSubdirectoryPaths
    }

    private func scheduleEffectiveExcludedCountRefresh() {
        effectiveExcludedCountTask?.cancel()

        let paths = preparedSubdirectoryPaths
        let excludedSet = Set(excludedSubdirectoryPaths)

        guard !paths.isEmpty, !excludedSet.isEmpty else {
            effectiveExcludedSubdirectoryCount = 0
            return
        }

        effectiveExcludedCountTask = Task {
            let count = await Task.detached(priority: .utility) {
                Self.countEffectivelyExcludedSubdirectoryPaths(in: paths, excludedSet: excludedSet)
            }.value

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                effectiveExcludedSubdirectoryCount = count
            }
        }
    }

    private func normalizeInitialExclusionSelectionIfNeeded() {
        guard !didNormalizeInitialExclusionSelection else {
            return
        }

        // Keep normalization side-effect free so opening/canceling the dialog
        // never mutates pending exclusions in the parent sheet.
        didNormalizeInitialExclusionSelection = true
    }

    private static func countEffectivelyExcludedSubdirectoryPaths(
        in paths: [String],
        excludedSet: Set<String>
    ) -> Int {
        paths.reduce(into: 0) { count, path in
            let isExcluded = excludedSet.contains { excludedPath in
                if excludedPath == path {
                    return true
                }

                let prefix = excludedPath.hasSuffix("/") ? excludedPath : excludedPath + "/"
                return path.hasPrefix(prefix)
            }

            if isExcluded {
                count += 1
            }
        }
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
        if isExcludedByAncestor {
            return "Inherited"
        }

        return isEffectivelyExcluded ? "Deactivated" : "Active"
    }

    private var statusSymbol: String {
        if isExcludedByAncestor {
            return "arrow.turn.down.right"
        }

        return isEffectivelyExcluded ? "slash.circle.fill" : "checkmark.circle.fill"
    }

    private var statusHint: String {
        if isExcludedByAncestor {
            return "Inherited from parent"
        }

        return isEffectivelyExcluded ? "Click to activate" : "Click to deactivate"
    }

    private var toggleTitle: String {
        isExplicitlyExcluded ? "Activate" : "Deactivate"
    }

    private var statusTint: AnyShapeStyle {
        isEffectivelyExcluded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
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

                Image(systemName: isEffectivelyExcluded ? "folder.badge.minus" : "folder.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isEffectivelyExcluded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label("\(node.subdirectoryCount)", systemImage: "folder")
                        Label("\(node.markdownFileCount)", systemImage: "doc.text")
                    }
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Label(statusTitle, systemImage: statusSymbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    isEffectivelyExcluded
                                        ? Color.secondary.opacity(0.10)
                                        : Color.green.opacity(0.13)
                                )
                        )

                    Button(toggleTitle) {
                        toggleExclusion()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 10.5, weight: .semibold))
                    .disabled(!canToggle)
                    .accessibilityHint(statusHint)
                }
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEffectivelyExcluded ? Color.secondary.opacity(0.08) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
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
        let prefix = node.path.hasSuffix("/") ? node.path : node.path + "/"

        if isExplicitlyExcluded {
            next = next.filter { path in
                guard path != node.path else {
                    return false
                }

                return !path.hasPrefix(prefix)
            }
        } else {
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

private struct FolderWatchDirectoryScanProgress: Equatable {
    let scannedDirectoryCount: Int
    let estimatedTotalDirectoryCount: Int

    var fractionCompleted: Double {
        guard estimatedTotalDirectoryCount > 0 else {
            return 0
        }

        let progress = Double(scannedDirectoryCount) / Double(estimatedTotalDirectoryCount)
        return max(0, min(progress, 1))
    }
}

private struct FolderWatchDirectoryNode: Identifiable, Equatable, Sendable {
    let path: String
    let name: String
    var children: [FolderWatchDirectoryNode]
    var subdirectoryCount: Int
    var markdownFileCount: Int

    var id: String { path }
}

private final class FolderWatchDirectoryScanModel: ObservableObject {
    nonisolated private enum ScanLimit {
        static let maximumTraversalDepth = ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth
        static let maximumVisitedDirectories = 20_000
        static let maximumSupportedSubdirectoryCount = ReaderFolderWatchPerformancePolicy.maximumSupportedSubdirectoryCount
    }

    @Published private(set) var isLoading = false
    @Published private(set) var scanProgress: FolderWatchDirectoryScanProgress?
    @Published private(set) var didExceedSupportedSubdirectoryLimit = false
    @Published private(set) var rootNode: FolderWatchDirectoryNode?
    @Published private(set) var allSubdirectoryPaths: [String] = []
    @Published private(set) var summary: FolderWatchDirectoryScanSummary?

    private var activeTask: Task<Void, Never>?
    private static let cache = FolderWatchDirectoryScanCache()
    private static let cacheableSubdirectoryThreshold = 2_000

    func reset() {
        activeTask?.cancel()
        activeTask = nil
        isLoading = false
        scanProgress = nil
        didExceedSupportedSubdirectoryLimit = false
        rootNode = nil
        allSubdirectoryPaths = []
        summary = nil
    }

    func scan(folderURL: URL) {
        activeTask?.cancel()
        isLoading = true
        scanProgress = FolderWatchDirectoryScanProgress(
            scannedDirectoryCount: 0,
            estimatedTotalDirectoryCount: ScanLimit.maximumVisitedDirectories
        )
        didExceedSupportedSubdirectoryLimit = false
        rootNode = nil
        allSubdirectoryPaths = []
        summary = nil

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let cacheKey = Self.cacheKey(for: normalizedFolderURL)
        activeTask = Task {
            if let cacheKey,
               let cachedResult = await Self.cache.cachedResult(for: cacheKey) {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run { [weak self] in
                    self?.applyScanResult(cachedResult)
                }
                return
            }

            let result = await Task.detached(priority: .utility) {
                Self.buildTree(at: normalizedFolderURL) { scannedDirectoryCount in
                    guard scannedDirectoryCount == 1 || scannedDirectoryCount.isMultiple(of: 32) else {
                        return
                    }

                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.isLoading else {
                            return
                        }

                        self.scanProgress = FolderWatchDirectoryScanProgress(
                            scannedDirectoryCount: scannedDirectoryCount,
                            estimatedTotalDirectoryCount: ScanLimit.maximumVisitedDirectories
                        )
                    }
                }
            }.value

            guard !Task.isCancelled else {
                return
            }

            if let cacheKey,
               Self.shouldCache(result: result) {
                await Self.cache.store(result, for: cacheKey)
            }

            await MainActor.run { [weak self] in
                self?.applyScanResult(result)
            }
        }
    }

    @MainActor
    private func applyScanResult(_ result: FolderWatchDirectoryScanResult) {
        isLoading = false
        scanProgress = nil
        didExceedSupportedSubdirectoryLimit = result.didExceedSupportedSubdirectoryLimit

        if result.didExceedSupportedSubdirectoryLimit {
            rootNode = nil
            allSubdirectoryPaths = []
            summary = nil
            return
        }

        rootNode = result.rootNode
        allSubdirectoryPaths = result.allSubdirectoryPaths

        if let rootNode {
            summary = FolderWatchDirectoryScanSummary(
                subdirectoryCount: rootNode.subdirectoryCount,
                markdownFileCount: rootNode.markdownFileCount
            )
        } else {
            summary = nil
        }
    }

    nonisolated private static func buildTree(
        at folderURL: URL,
        onDirectoryScanned: @escaping @Sendable (Int) -> Void
    ) -> FolderWatchDirectoryScanResult {
        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        guard (try? normalizedFolderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return FolderWatchDirectoryScanResult(
                rootNode: nil,
                allSubdirectoryPaths: [],
                didExceedSupportedSubdirectoryLimit: false
            )
        }

        var scanState = DirectoryScanTraversalState()
        var visitedDirectoryPaths = Set<String>()
        let rootNode = buildNode(
            at: normalizedFolderURL,
            depth: 0,
            visitedDirectoryPaths: &visitedDirectoryPaths,
            scanState: &scanState,
            onDirectoryScanned: onDirectoryScanned
        )

        return FolderWatchDirectoryScanResult(
            rootNode: rootNode,
            allSubdirectoryPaths: rootNode?.children.flatMap { collectPaths(from: $0) }.sorted() ?? [],
            didExceedSupportedSubdirectoryLimit: scanState.didExceedSupportedSubdirectoryLimit
        )
    }

    nonisolated private static func collectPaths(from node: FolderWatchDirectoryNode) -> [String] {
        [node.path] + node.children.flatMap { collectPaths(from: $0) }
    }

    nonisolated private static func shouldCache(result: FolderWatchDirectoryScanResult) -> Bool {
        guard !result.didExceedSupportedSubdirectoryLimit,
              let rootNode = result.rootNode else {
            return false
        }

        return rootNode.subdirectoryCount <= cacheableSubdirectoryThreshold
    }

    nonisolated private static func cacheKey(for normalizedFolderURL: URL) -> FolderWatchDirectoryScanCacheKey? {
        let values = try? normalizedFolderURL.resourceValues(
            forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        )

        guard values?.isDirectory == true else {
            return nil
        }

        let resourceIdentifier = values?.fileResourceIdentifier.map(String.init(describing:)) ?? "none"
        let contentModificationStamp = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fingerprint = "\(resourceIdentifier)|\(Int64(contentModificationStamp * 1_000))"

        return FolderWatchDirectoryScanCacheKey(folderPath: normalizedFolderURL.path, folderFingerprint: fingerprint)
    }

    nonisolated private static func buildNode(
        at directoryURL: URL,
        depth: Int,
        visitedDirectoryPaths: inout Set<String>,
        scanState: inout DirectoryScanTraversalState,
        onDirectoryScanned: @escaping @Sendable (Int) -> Void
    ) -> FolderWatchDirectoryNode? {
        guard !scanState.didExceedSupportedSubdirectoryLimit else {
            return nil
        }

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

        let scannedSubdirectoryCount = max(0, visitedDirectoryPaths.count - 1)
        onDirectoryScanned(scannedSubdirectoryCount)

        if scannedSubdirectoryCount > ScanLimit.maximumSupportedSubdirectoryCount {
            scanState.didExceedSupportedSubdirectoryLimit = true
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
            guard !scanState.didExceedSupportedSubdirectoryLimit else {
                return nil
            }

            let normalizedEntry = ReaderFileRouting.normalizedFileURL(entry)
            let values = try? normalizedEntry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])

            if values?.isSymbolicLink == true {
                continue
            }

            if values?.isDirectory == true {
                if let childNode = buildNode(
                    at: normalizedEntry,
                    depth: depth + 1,
                    visitedDirectoryPaths: &visitedDirectoryPaths,
                    scanState: &scanState,
                    onDirectoryScanned: onDirectoryScanned
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

private struct FolderWatchDirectoryScanResult: Sendable {
    let rootNode: FolderWatchDirectoryNode?
    let allSubdirectoryPaths: [String]
    let didExceedSupportedSubdirectoryLimit: Bool
}

private struct DirectoryScanTraversalState: Sendable {
    var didExceedSupportedSubdirectoryLimit = false
}

private struct FolderWatchDirectoryScanCacheKey: Hashable, Sendable {
    let folderPath: String
    let folderFingerprint: String
}

private struct FolderWatchDirectoryScanCacheEntry: Sendable {
    let result: FolderWatchDirectoryScanResult
    let insertedAt: Date
}

private actor FolderWatchDirectoryScanCache {
    private let maximumEntries = 4
    private let maximumEntryAge: TimeInterval = 30
    private var entriesByKey: [FolderWatchDirectoryScanCacheKey: FolderWatchDirectoryScanCacheEntry] = [:]
    private var keyOrder: [FolderWatchDirectoryScanCacheKey] = []

    func cachedResult(for key: FolderWatchDirectoryScanCacheKey) -> FolderWatchDirectoryScanResult? {
        guard let entry = entriesByKey[key] else {
            return nil
        }

        if Date().timeIntervalSince(entry.insertedAt) > maximumEntryAge {
            remove(key)
            return nil
        }

        touch(key)
        return entry.result
    }

    func store(_ result: FolderWatchDirectoryScanResult, for key: FolderWatchDirectoryScanCacheKey) {
        entriesByKey[key] = FolderWatchDirectoryScanCacheEntry(result: result, insertedAt: Date())
        touch(key)

        while keyOrder.count > maximumEntries,
              let oldestKey = keyOrder.first {
            keyOrder.removeFirst()
            entriesByKey.removeValue(forKey: oldestKey)
        }
    }

    private func remove(_ key: FolderWatchDirectoryScanCacheKey) {
        entriesByKey.removeValue(forKey: key)
        keyOrder.removeAll(where: { $0 == key })
    }

    private func touch(_ key: FolderWatchDirectoryScanCacheKey) {
        keyOrder.removeAll(where: { $0 == key })
        keyOrder.append(key)
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
    let openModeLabel: String
    let scopeLabel: String
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

            HStack(spacing: 8) {
                FolderWatchMetricPill(
                    title: openModeLabel,
                    symbol: "bolt.horizontal.circle"
                )

                FolderWatchMetricPill(
                    title: scopeLabel,
                    symbol: "arrow.triangle.branch"
                )

                Spacer()
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
