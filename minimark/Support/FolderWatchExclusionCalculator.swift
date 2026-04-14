import Foundation

/// Shared algorithm for calculating how many subdirectory paths are effectively excluded
/// by a set of explicitly excluded paths — accounting for ancestor inheritance.
///
/// Used by both `FolderWatchOptionsSheet` and `LargeFolderExclusionDialog` to avoid
/// duplicating the exclusion counting logic.
nonisolated enum FolderWatchExclusionCalculator {

    /// Returns the number of paths in `paths` that are effectively excluded,
    /// either by direct membership in `excludedPaths` or by having an ancestor in the set.
    static func countEffectivelyExcludedPaths(
        in paths: [String],
        excludedPaths: Set<String>
    ) -> Int {
        guard !paths.isEmpty, !excludedPaths.isEmpty else {
            return 0
        }

        let normalizedExcludedSet = Set(excludedPaths.map(normalizedDirectoryPath))
        let normalizedPaths = paths.map(normalizedDirectoryPath)

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

    /// Returns `true` when `path` is either directly contained in `excludedSet`
    /// or has an ancestor path that is contained in `excludedSet`.
    static func isPathExcludedBySelfOrAncestor(
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

    /// Removes trailing slashes from a path, preserving the root `/`.
    static func normalizedDirectoryPath(_ path: String) -> String {
        guard path.count > 1 else {
            return path
        }

        var normalizedPath = path
        while normalizedPath.count > 1, normalizedPath.hasSuffix("/") {
            normalizedPath.removeLast()
        }

        return normalizedPath
    }
}
