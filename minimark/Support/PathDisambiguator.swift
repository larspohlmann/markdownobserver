import Foundation

/// Shared algorithms for disambiguating paths that share the same leaf component.
///
/// Used by sidebar group headers and recent-file menu titles to compute
/// the shortest unique display name for each path.
nonisolated enum PathDisambiguator {

    /// Batch-disambiguate a set of paths by their leaf component,
    /// progressively adding parent components until every display name is unique.
    ///
    /// Empty paths are mapped to `"Untitled"`.
    static func disambiguatedDisplayNames(
        for paths: [String]
    ) -> [String: String] {
        guard !paths.isEmpty else { return [:] }

        let nonEmpty = paths.filter { !$0.isEmpty }
        let untitled = paths.filter { $0.isEmpty }

        guard nonEmpty.count > 1 || !untitled.isEmpty else {
            if let single = nonEmpty.first {
                let name = (single as NSString).lastPathComponent
                return [single: name]
            }
            return untitled.isEmpty ? [:] : ["": "Untitled"]
        }

        let components: [String: [String]] = Dictionary(uniqueKeysWithValues:
            nonEmpty.map { path in
                let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                return (path, parts)
            }
        )

        // Start with just the last component (folder name)
        var names: [String: String] = Dictionary(uniqueKeysWithValues:
            nonEmpty.map { ($0, components[$0]?.last ?? $0) }
        )

        // If there are duplicates, add parent components until unique
        let maxDepth = components.values.map(\.count).max() ?? 1
        var depth = 1

        while depth < maxDepth {
            let duplicateNames = Dictionary(grouping: nonEmpty, by: { names[$0]! })
                .filter { $0.value.count > 1 }

            if duplicateNames.isEmpty { break }

            depth += 1
            for (_, duplicatePaths) in duplicateNames {
                for path in duplicatePaths {
                    guard let parts = components[path] else { continue }
                    let startIndex = max(0, parts.count - depth)
                    names[path] = parts[startIndex...].joined(separator: "/")
                }
            }
        }

        if !untitled.isEmpty {
            names[""] = "Untitled"
        }

        return names
    }

    /// For a single path among siblings sharing the same display name,
    /// return the shortest parent-directory suffix that makes it unique.
    ///
    /// Pass a pre-built `parentComponentsByPath` when calling this repeatedly
    /// for the same set of paths (e.g. in a batch menu-title pass) to avoid
    /// recomputing parent components on every call.
    ///
    /// Returns `nil` if the path has no parent components.
    static func uniqueParentSuffix(
        for path: String,
        among siblingPaths: [String],
        parentComponentsByPath: [String: [String]]? = nil
    ) -> String? {
        let lookup: (String) -> [String] = { parentComponentsByPath?[$0] ?? parentComponents(for: $0) }
        let siblingParentComponents = siblingPaths.map(lookup)
        let targetParentComponents = lookup(path)
        guard !targetParentComponents.isEmpty else {
            return nil
        }

        let maximumDepth = siblingParentComponents.map(\.count).max() ?? 0
        for suffixLength in 1...maximumDepth {
            let targetSuffix = suffix(parentComponents: targetParentComponents, count: suffixLength)
            let siblingSuffixes = siblingParentComponents.map { suffix(parentComponents: $0, count: suffixLength) }

            if siblingSuffixes.filter({ $0 == targetSuffix }).count == 1 {
                return targetSuffix
            }
        }

        return targetParentComponents.joined(separator: "/")
    }

    // MARK: - Helpers

    static func parentComponents(for path: String) -> [String] {
        URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
    }

    private static func suffix(parentComponents: [String], count: Int) -> String {
        let suffixCount = min(count, parentComponents.count)
        return parentComponents.suffix(suffixCount).joined(separator: "/")
    }
}
