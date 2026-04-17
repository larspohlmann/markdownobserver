import SwiftUI

/// Testable view model that owns all policy/threshold calculations and status text
/// generation for ``FolderWatchOptionsSheet``.
///
/// The view model reads scan state, scope, and exclusion selections and exposes
/// derived computed properties that the sheet's SwiftUI body consumes for display
/// and action gating.
struct FolderWatchOptionsViewModel {

    // MARK: - Inputs

    var folderURL: URL?
    var scope: FolderWatchScope = .selectedFolderOnly
    var excludedSubdirectoryPaths: [String] = []

    /// Total subdirectory count from the completed scan, or `nil` while loading / no scan.
    var subdirectoryCount: Int?

    /// Markdown file count from the completed scan.
    var markdownFileCount: Int?

    /// All subdirectory paths discovered by the scan model.
    var allSubdirectoryPaths: [String] = []

    /// Whether the scan model is currently scanning.
    var isLoading: Bool = false

    /// Whether the scan model exceeded the supported subdirectory limit during traversal.
    var didExceedSupportedSubdirectoryLimit: Bool = false

    // MARK: - Derived computed properties

    var normalizedExcludedSubdirectoryPaths: [String] {
        guard let folderURL else {
            return []
        }

        let normalizedFolderURL = ReaderFileRouting.normalizedFileURL(folderURL)
        let normalizedFolderPath = normalizedFolderURL.path
        let folderPathPrefix = normalizedFolderPath.hasSuffix("/")
            ? normalizedFolderPath
            : normalizedFolderPath + "/"

        let normalized = excludedSubdirectoryPaths.compactMap { path -> String? in
            guard !path.isEmpty else {
                return nil
            }

            let trimmedPath = FolderWatchExclusionCalculator.normalizedDirectoryPath(path)
            if trimmedPath.hasPrefix(folderPathPrefix), trimmedPath != normalizedFolderPath {
                return trimmedPath
            }

            let normalizedPath = ReaderFileRouting.normalizedFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            ).path
            guard normalizedPath.hasPrefix(folderPathPrefix),
                  normalizedPath != normalizedFolderPath else {
                return nil
            }

            return normalizedPath
        }

        return Array(Set(normalized)).sorted()
    }

    var effectiveExcludedSubdirectoryCount: Int {
        FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: allSubdirectoryPaths,
            excludedPaths: Set(normalizedExcludedSubdirectoryPaths)
        )
    }

    var remainingSubdirectoriesToDeactivateCount: Int {
        guard let subdirectoryCount else {
            return 0
        }

        let activeSubdirectoryCount = max(0, subdirectoryCount - effectiveExcludedSubdirectoryCount)
        return max(0, activeSubdirectoryCount - FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold)
    }

    var exceedsSupportedSubdirectoryLimit: Bool {
        scope == .includeSubfolders && didExceedSupportedSubdirectoryLimit
    }

    var requiresHardLimitRefusal: Bool {
        exceedsSupportedSubdirectoryLimit
    }

    var requiresExclusionSelectionBeforeStart: Bool {
        guard !requiresHardLimitRefusal else {
            return false
        }

        guard scope == .includeSubfolders,
              let subdirectoryCount,
              subdirectoryCount > FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold else {
            return false
        }

        return remainingSubdirectoriesToDeactivateCount > 0
    }

    var thresholdWarningVisible: Bool {
        guard !requiresHardLimitRefusal else {
            return false
        }

        guard let subdirectoryCount else {
            return false
        }

        return subdirectoryCount > FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold
    }

    var thresholdWarningTitle: String {
        guard let subdirectoryCount else {
            return "Large tree optimization"
        }

        return "\(subdirectoryCount) subdirectories detected"
    }

    var thresholdWarningDetail: String {
        let selectedCount = normalizedExcludedSubdirectoryPaths.count
        if selectedCount > 0 && remainingSubdirectoriesToDeactivateCount == 0 {
            let noun = selectedCount == 1 ? "subdirectory" : "subdirectories"
            return "Threshold satisfied with \(selectedCount) \(noun) deactivated. You can start watching now."
        }

        if selectedCount > 0 {
            let noun = remainingSubdirectoriesToDeactivateCount == 1 ? "subdirectory" : "subdirectories"
            return "Deactivate \(remainingSubdirectoriesToDeactivateCount) more \(noun) to reach the optimization threshold."
        }

        return "This exceeds the optimization threshold of \(FolderWatchPerformancePolicy.exclusionPromptSubdirectoryThreshold). Deactivate one or more subdirectories before starting to reduce freeze risk."
    }

    var optimizationCardTitle: String {
        guard scope == .includeSubfolders else {
            return "Subfolder optimization"
        }

        guard !isLoading else {
            return "Scanning subfolders"
        }

        if requiresHardLimitRefusal {
            return "Folder too large for Include Subfolders"
        }

        return thresholdWarningVisible
            ? thresholdWarningTitle
            : "Tree size is within optimization threshold"
    }

    var optimizationCardDetail: String {
        guard scope == .includeSubfolders else {
            return "Enable Include Subfolders to evaluate tree size and optimization guidance."
        }

        guard !isLoading else {
            return "Collecting subfolder metrics to evaluate large-tree performance."
        }

        if requiresHardLimitRefusal {
            return "Detected more than \(FolderWatchPerformancePolicy.maximumSupportedSubdirectoryCount) subdirectories. To avoid long freezes, this configuration cannot be started. Choose Selected Folder instead."
        }

        return thresholdWarningVisible
            ? thresholdWarningDetail
            : "No exclusions required. You can start watching with subfolders enabled."
    }

    var optimizationCardTone: FolderWatchLargeTreeWarningCard.Tone {
        guard scope == .includeSubfolders else {
            return .neutral
        }

        guard !isLoading else {
            return .neutral
        }

        if requiresHardLimitRefusal {
            return .warning
        }

        return thresholdWarningVisible ? .warning : .success
    }

    var startActionStatusText: String {
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

    var startActionStatusSymbol: String {
        if requiresHardLimitRefusal {
            return "xmark.octagon.fill"
        }

        if requiresExclusionSelectionBeforeStart {
            return "exclamationmark.triangle.fill"
        }

        return thresholdWarningVisible ? "checkmark.shield.fill" : "checkmark.circle.fill"
    }

    var startActionStatusColor: AnyShapeStyle {
        if requiresHardLimitRefusal {
            return AnyShapeStyle(.red)
        }

        if requiresExclusionSelectionBeforeStart {
            return AnyShapeStyle(.orange)
        }

        return AnyShapeStyle(.green)
    }
}
