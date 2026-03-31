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
        static let contentSpacing: CGFloat = 16
        static let width: CGFloat = 480
        static let pickerWidth: CGFloat = 230
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

    private var normalizedExcludedSubdirectoryPaths: [String] {
        guard let folderURL else {
            return []
        }

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let normalizedFolderPath = normalizedFolderURL.path
        let folderPathPrefix = normalizedFolderPath.hasSuffix("/") ? normalizedFolderPath : normalizedFolderPath + "/"

        let normalized = excludedSubdirectoryPaths.compactMap { path -> String? in
            guard !path.isEmpty else {
                return nil
            }

            // Fast-path common case: values emitted by the scan model are already normalized absolute paths.
            let trimmedPath = Self.trimTrailingSlash(from: path)
            if trimmedPath.hasPrefix(folderPathPrefix), trimmedPath != normalizedFolderPath {
                return trimmedPath
            }

            let normalizedPath = ReaderFileRouting.normalizedFileURL(URL(fileURLWithPath: path, isDirectory: true)).path
            guard normalizedPath.hasPrefix(folderPathPrefix), normalizedPath != normalizedFolderPath else {
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
        Self.countEffectivelyExcludedSubdirectoryPaths(
            in: allScannedSubdirectoryPaths,
            excludedPaths: normalizedExcludedSubdirectoryPaths
        )
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

    private var showsAdvancedSubfolderDetails: Bool {
        scope == .includeSubfolders
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
            // MARK: Header
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "binoculars.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Folder")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)

                    Text("Configure how file changes are monitored")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Folder bar
            let hasFolderSelection = folderURL != nil
            HStack(spacing: 10) {
                Image(systemName: hasFolderSelection ? "folder.fill" : "folder.badge.questionmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(hasFolderSelection ? .primary : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFolderName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hasFolderSelection ? .primary : .secondary)
                        .lineLimit(1)

                    Text(selectedFolderPath)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(selectedFolderPath)
                        .accessibilityLabel("Folder path")
                        .accessibilityValue(selectedFolderPath)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .accessibilityIdentifier("folder-watch-summary-card")

            // MARK: Option rows
            VStack(spacing: 0) {
                HStack {
                    Text("On start")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Picker("Watch start mode", selection: openModeSelectionBinding) {
                        Text("Open Existing")
                            .tag(ReaderFolderWatchOpenMode.openAllMarkdownFiles)
                        Text("Watch Only")
                            .tag(ReaderFolderWatchOpenMode.watchChangesOnly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Metrics.pickerWidth)
                    .accessibilityLabel("Watch start mode")
                }
                .padding(.vertical, 10)

                Divider()

                HStack {
                    Text("Scope")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Picker("Folder scope", selection: scopeSelectionBinding) {
                        Text("Selected Folder")
                            .tag(ReaderFolderWatchScope.selectedFolderOnly)
                        Text("Include Subfolders")
                            .tag(ReaderFolderWatchScope.includeSubfolders)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: Metrics.pickerWidth)
                    .accessibilityLabel("Folder scope")
                }
                .padding(.vertical, 10)

                if showsAdvancedSubfolderDetails {
                    Divider()

                    if directoryScanModel.isLoading {
                        let scanText = directoryScanModel.scanProgress.map {
                            "Scanning... \($0.scannedDirectoryCount) folders"
                        } ?? "Scanning subfolders..."

                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)

                            Text(scanText)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if let summary = directoryScanModel.summary {
                        HStack(spacing: 8) {
                            FolderWatchMetricPill(
                                title: "\(summary.subdirectoryCount) " +
                                    (summary.subdirectoryCount == 1 ? "subdirectory" : "subdirectories"),
                                symbol: "folder.badge.gearshape"
                            )

                            FolderWatchMetricPill(
                                title: "\(summary.markdownFileCount) " +
                                    (summary.markdownFileCount == 1 ? "file" : "files"),
                                symbol: "doc.text.magnifyingglass"
                            )
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }

            // MARK: Summary
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 3)

                Text(selectionSummary)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // MARK: Warning card (only when tree exceeds threshold)
            if showsAdvancedSubfolderDetails && (thresholdWarningVisible || requiresHardLimitRefusal) {
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

            Divider()

            // MARK: Actions
            HStack {
                if showsAdvancedSubfolderDetails && (requiresHardLimitRefusal || requiresExclusionSelectionBeforeStart) {
                    Label(startActionStatusText, systemImage: startActionStatusSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(startActionStatusColor)
                }

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
        .onChange(of: directoryScanModel.summary?.subdirectoryCount) { _, newCount in
            guard let newCount, newCount > ReaderFolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold,
                  ProcessInfo.processInfo.environment[
                      ReaderUITestLaunchConfiguration.screenshotOpenExclusionEnvironmentKey
                  ] == "true" else { return }

            // Pre-set excluded/expanded paths from env vars.
            // Env vars contain relative names (e.g. "DerivedData,node_modules").
            // Convert to absolute paths by matching against scan results.
            let allPaths = directoryScanModel.summary.map { _ in
                directoryScanModel.allSubdirectoryPaths
            } ?? []

            if let excludedEnv = ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotExcludedPathsEnvironmentKey
            ], !excludedEnv.isEmpty {
                let excludeNames = Set(excludedEnv.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                excludedSubdirectoryPaths = allPaths.filter { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return excludeNames.contains(name)
                }
            }

            if let expandedEnv = ProcessInfo.processInfo.environment[
                ReaderUITestLaunchConfiguration.screenshotExpandedPathsEnvironmentKey
            ], !expandedEnv.isEmpty {
                let expandNames = Set(expandedEnv.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                expandedDirectoryPaths = Set(allPaths.filter { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return expandNames.contains(name)
                })
            }

            isLargeTreeDialogPresented = true
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

    nonisolated private static func trimTrailingSlash(from path: String) -> String {
        guard path.count > 1 else {
            return path
        }

        var trimmedPath = path
        while trimmedPath.count > 1, trimmedPath.hasSuffix("/") {
            trimmedPath.removeLast()
        }

        return trimmedPath
    }

    nonisolated private static func countEffectivelyExcludedSubdirectoryPaths(
        in paths: [String],
        excludedPaths: [String]
    ) -> Int {
        guard !paths.isEmpty, !excludedPaths.isEmpty else {
            return 0
        }

        let normalizedExcludedSet = Set(excludedPaths.map(trimTrailingSlash(from:)))
        let normalizedPaths = paths.map(trimTrailingSlash(from:))

        if normalizedExcludedSet.count >= normalizedPaths.count,
           Set(normalizedPaths).isSubset(of: normalizedExcludedSet) {
            return normalizedPaths.count
        }

        return normalizedPaths.reduce(into: 0) { count, path in
            if isPathExcludedBySelfOrAncestor(path, excludedSet: normalizedExcludedSet) {
                count += 1
            }
        }
    }

    nonisolated private static func isPathExcludedBySelfOrAncestor(
        _ path: String,
        excludedSet: Set<String>
    ) -> Bool {
        if excludedSet.contains(path) {
            return true
        }

        var ancestorCandidate = path
        while let separatorIndex = ancestorCandidate.lastIndex(of: "/") {
            if separatorIndex == ancestorCandidate.startIndex {
                break
            }

            ancestorCandidate = String(ancestorCandidate[..<separatorIndex])
            if excludedSet.contains(ancestorCandidate) {
                return true
            }
        }

        return false
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

struct FolderWatchPrimaryActionButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    private var textStyle: AnyShapeStyle {
        if isEnabled {
            return AnyShapeStyle(.white)
        }
        return colorScheme == .dark
            ? AnyShapeStyle(.white.opacity(0.46))
            : AnyShapeStyle(.secondary)
    }

    private var fillColor: Color {
        if isEnabled { return tint }
        return colorScheme == .dark
            ? Color.secondary.opacity(0.16)
            : Color.secondary.opacity(0.12)
    }

    private var borderColor: Color {
        isEnabled ? Color.white.opacity(0.15) : Color.primary.opacity(0.06)
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

struct FolderWatchSecondaryActionButtonStyle: ButtonStyle {
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

struct FolderWatchLargeTreeWarningCard: View {
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
                    .accessibilityIdentifier("folder-watch-choose-subdirectories-button")
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

    private var footerNeedText: String {
        if remainingToDeactivateCount == 0 {
            return "Threshold met"
        }

        return "Need \(remainingToDeactivateCount) more"
    }

    private var progressRingFraction: Double {
        guard threshold > 0 else { return 0 }
        let fraction = Double(activeSubdirectoryCount) / Double(threshold)
        return min(1.0, fraction)
    }

    private var progressRingColor: Color {
        remainingToDeactivateCount == 0 ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: Header row
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optimize Large Folder Watch")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    if let summary = scanModel.summary {
                        Text("\(summary.subdirectoryCount) subdirectories found")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }

                    Label("Depth limit: \(ReaderFolderWatchPerformancePolicy.maximumIncludedSubfolderDepth) levels", systemImage: "arrow.down.to.line.compact")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.16))
                        )

                    HStack(spacing: 8) {
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
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 5)

                    Circle()
                        .trim(from: 0, to: progressRingFraction)
                        .stroke(progressRingColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 1) {
                        Text("\(activeSubdirectoryCount)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(progressRingColor)

                        Text("/\(threshold)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 70, height: 70)
            }

            // MARK: Status divider
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)

                Text(footerNeedText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(progressRingColor)
                    .fixedSize()

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
            }

            // MARK: Folder list
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
                                excludedSubdirectoryPathSet: excludedSet,
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

            // MARK: Footer
            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Start Watching") {
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
        .frame(width: 620)
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

    nonisolated private static func countEffectivelyExcludedSubdirectoryPaths(
        in paths: [String],
        excludedSet: Set<String>
    ) -> Int {
        guard !paths.isEmpty, !excludedSet.isEmpty else {
            return 0
        }

        let normalizedExcludedSet = Set(excludedSet.map(Self.normalizedDirectoryPath))
        let normalizedPaths = paths.map(Self.normalizedDirectoryPath)

        if normalizedExcludedSet.count >= normalizedPaths.count,
           Set(normalizedPaths).isSubset(of: normalizedExcludedSet) {
            return normalizedPaths.count
        }

        return normalizedPaths.reduce(into: 0) { count, path in
            if Self.isPathExcludedBySelfOrAncestor(path, excludedSet: normalizedExcludedSet) {
                count += 1
            }
        }
    }

    nonisolated private static func normalizedDirectoryPath(_ path: String) -> String {
        guard path.count > 1 else {
            return path
        }

        var normalizedPath = path
        while normalizedPath.count > 1, normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }

        return normalizedPath
    }

    nonisolated private static func isPathExcludedBySelfOrAncestor(
        _ path: String,
        excludedSet: Set<String>
    ) -> Bool {
        if excludedSet.contains(path) {
            return true
        }

        var ancestorCandidate = path
        while let separatorIndex = ancestorCandidate.lastIndex(of: "/") {
            if separatorIndex == ancestorCandidate.startIndex {
                break
            }

            ancestorCandidate = String(ancestorCandidate[..<separatorIndex])
            if excludedSet.contains(ancestorCandidate) {
                return true
            }
        }

        return false
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
    let excludedSubdirectoryPathSet: Set<String>
    @Binding var expandedDirectoryPaths: Set<String>
    @Binding var excludedSubdirectoryPaths: [String]

    private var isExplicitlyExcluded: Bool {
        excludedSubdirectoryPathSet.contains(node.path)
    }

    private var isExcludedByAncestor: Bool {
        guard !isExplicitlyExcluded else {
            return false
        }

        var ancestorCandidate = node.path
        while let separatorIndex = ancestorCandidate.lastIndex(of: "/") {
            if separatorIndex == ancestorCandidate.startIndex {
                break
            }

            ancestorCandidate = String(ancestorCandidate[..<separatorIndex])
            if excludedSubdirectoryPathSet.contains(ancestorCandidate) {
                return true
            }
        }

        return false
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

    private var isActive: Bool {
        !isEffectivelyExcluded
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isActive },
            set: { newValue in
                if newValue != isActive {
                    toggleExclusion()
                }
            }
        )
    }

    private var inlineStats: String {
        "\(node.subdirectoryCount) sub \u{00B7} \(node.markdownFileCount) files"
    }

    var body: some View {
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

                Image(systemName: isEffectivelyExcluded ? "folder.badge.minus" : "folder.fill")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isEffectivelyExcluded ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

                Text(node.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Text(inlineStats)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle(isOn: toggleBinding) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(!canToggle)
                .help(isExcludedByAncestor ? "Exclusion inherited from a parent folder" : "Toggle to include or exclude this folder")
                .accessibilityLabel("\(node.name)")
                .accessibilityValue(isEffectivelyExcluded ? (isExcludedByAncestor ? "Inherited" : "Deactivated") : "Active")
            }
            .padding(.leading, CGFloat(level) * 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .opacity(isEffectivelyExcluded ? 0.5 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isEffectivelyExcluded ? Color.secondary.opacity(0.04) : Color.clear)
            )

            if hasChildren && isExpanded {
                ForEach(node.children) { child in
                    FolderWatchTreeNodeRow(
                        node: child,
                        level: level + 1,
                        excludedSubdirectoryPathSet: excludedSubdirectoryPathSet,
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

