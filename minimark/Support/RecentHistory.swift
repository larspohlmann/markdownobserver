import Foundation

nonisolated enum RecentHistory {
    private struct MenuDisambiguationContext {
        let siblingPathsByDisplayName: [String: [String]]
        let parentComponentsByPath: [String: [String]]

        func title(displayName: String, pathText: String) -> String {
            let siblingPaths = siblingPathsByDisplayName[displayName] ?? []
            guard siblingPaths.count > 1,
                  let suffix = PathDisambiguator.uniqueParentSuffix(
                    for: pathText,
                    among: siblingPaths,
                    parentComponentsByPath: parentComponentsByPath
                  ) else {
                return displayName
            }

            return "\(displayName) (\(suffix))"
        }
    }

    static func insertingUniqueFile(
        _ fileURL: URL,
        into existingEntries: [RecentOpenedFile]
    ) -> [RecentOpenedFile] {
        let newEntry = RecentOpenedFile(fileURL: fileURL)
        let deduplicated = existingEntries.filter { $0.filePath != newEntry.filePath }
        return Array(([newEntry] + deduplicated).prefix(RecentOpenedFile.maximumCount))
    }

    static func insertingUniqueWatchedFolder(
        _ folderURL: URL,
        options: FolderWatchOptions,
        into existingEntries: [RecentWatchedFolder]
    ) -> [RecentWatchedFolder] {
        let newEntry = RecentWatchedFolder(folderURL: folderURL, options: options)
        let deduplicated = existingEntries.filter { $0.folderPath != newEntry.folderPath }
        return Array(([newEntry] + deduplicated).prefix(RecentWatchedFolder.maximumCount))
    }

    static func menuTitle(
        for entry: RecentOpenedFile,
        among entries: [RecentOpenedFile]
    ) -> String {
        menuTitle(
            for: entry,
            among: entries,
            displayName: \.displayName,
            pathText: \.pathText
        )
    }

    static func menuTitles(for entries: [RecentOpenedFile]) -> [String: String] {
        menuTitles(for: entries, keyPath: \.filePath, displayName: \.displayName, pathText: \.pathText)
    }

    static func menuTitle(
        for entry: RecentWatchedFolder,
        among entries: [RecentWatchedFolder]
    ) -> String {
        let baseTitle = menuTitle(
            for: entry,
            among: entries,
            displayName: \.displayName,
            pathText: \.pathText
        )

        let excludedCount = entry.options.excludedSubdirectoryPaths.count
        guard entry.options.scope == .includeSubfolders, excludedCount > 0 else {
            return baseTitle
        }

        let noun = excludedCount == 1 ? "folder" : "folders"
        return "\(baseTitle) [\(excludedCount) filtered \(noun)]"
    }

    static func menuTitles(for entries: [RecentWatchedFolder]) -> [String: String] {
        let baseTitlesByPath = menuTitles(
            for: entries,
            keyPath: \.folderPath,
            displayName: \.displayName,
            pathText: \.pathText
        )

        return Dictionary(entries.map { entry in
            let excludedCount = entry.options.excludedSubdirectoryPaths.count
            guard entry.options.scope == .includeSubfolders, excludedCount > 0 else {
                return (entry.folderPath, baseTitlesByPath[entry.folderPath] ?? entry.displayName)
            }

            let noun = excludedCount == 1 ? "folder" : "folders"
            let baseTitle = baseTitlesByPath[entry.folderPath] ?? entry.displayName
            return (entry.folderPath, "\(baseTitle) [\(excludedCount) filtered \(noun)]")
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func menuTitle<Entry>(
        for entry: Entry,
        among entries: [Entry],
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> String {
        let context = buildMenuDisambiguationContext(
            for: entries,
            displayName: displayName,
            pathText: pathText
        )
        return context.title(
            displayName: entry[keyPath: displayName],
            pathText: entry[keyPath: pathText]
        )
    }

    private static func menuTitles<Entry>(
        for entries: [Entry],
        keyPath: KeyPath<Entry, String>,
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> [String: String] {
        let context = buildMenuDisambiguationContext(
            for: entries,
            displayName: displayName,
            pathText: pathText
        )

        return Dictionary(entries.map { entry in
            let key = entry[keyPath: keyPath]
            let resolvedDisplayName = entry[keyPath: displayName]
            return (
                key,
                context.title(
                    displayName: resolvedDisplayName,
                    pathText: entry[keyPath: pathText]
                )
            )
        }, uniquingKeysWith: { first, _ in first })
    }

    private static func buildMenuDisambiguationContext<Entry>(
        for entries: [Entry],
        displayName: KeyPath<Entry, String>,
        pathText: KeyPath<Entry, String>
    ) -> MenuDisambiguationContext {
        let siblingPathsByDisplayName = Dictionary(grouping: entries, by: { $0[keyPath: displayName] })
            .mapValues { groupedEntries in
                groupedEntries.map { $0[keyPath: pathText] }
            }

        let allPaths = siblingPathsByDisplayName.values.flatMap { $0 }
        let parentComponentsByPath = Dictionary(allPaths.map { path in
            (path, PathDisambiguator.parentComponents(for: path))
        }, uniquingKeysWith: { first, _ in first })

        return MenuDisambiguationContext(
            siblingPathsByDisplayName: siblingPathsByDisplayName,
            parentComponentsByPath: parentComponentsByPath
        )
    }
}
