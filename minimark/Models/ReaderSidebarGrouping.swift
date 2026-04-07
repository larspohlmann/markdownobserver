import Foundation

@MainActor
enum ReaderSidebarGrouping: Equatable {
    case flat([ReaderSidebarDocumentController.Document])
    case grouped([Group])

    struct Group: Identifiable, Equatable {
        let id: String
        let displayName: String
        let directoryURL: URL?
        let documents: [ReaderSidebarDocumentController.Document]
        let indicatorStates: [ReaderDocumentIndicatorState]
        let indicatorPulseToken: Int
        let newestModificationDate: Date?
        let isPinned: Bool
    }

    var firstDocumentID: UUID? {
        switch self {
        case .flat(let documents):
            return documents.first?.id
        case .grouped(let groups):
            return groups.first?.documents.first?.id
        }
    }

    var allDocumentIDs: [UUID] {
        switch self {
        case .flat(let documents):
            return documents.map(\.id)
        case .grouped(let groups):
            return groups.flatMap { $0.documents.map(\.id) }
        }
    }

    static func group(
        _ documents: [ReaderSidebarDocumentController.Document],
        sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst,
        directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]? = nil,
        pinnedGroupIDs: Set<String> = [],
        precomputedIndicatorStates: [String: [ReaderDocumentIndicatorState]]? = nil,
        precomputedIndicatorPulseTokens: [String: Int]? = nil
    ) -> ReaderSidebarGrouping {
        let grouped = Dictionary(grouping: documents) { document -> String in
            directoryURL(for: document)?.path(percentEncoded: false) ?? ""
        }
        let orderedDirectoryPaths = orderedUniqueDirectoryPaths(
            from: directoryOrderSourceDocuments ?? documents
        )

        let hasUntitled = grouped[""] != nil
        let directoryCount = hasUntitled ? grouped.count - 1 : grouped.count

        guard directoryCount > 1 || (hasUntitled && directoryCount > 0) else {
            return .flat(documents)
        }

        let displayNames = disambiguatedDisplayNames(for: Array(grouped.keys))

        let groups: [Group] = orderedDirectoryPaths.compactMap { directoryPath in
            guard let docs = grouped[directoryPath] else {
                return nil
            }
            let dirURL = docs.first.flatMap { directoryURL(for: $0) }
            let indicatorStates = precomputedIndicatorStates?[directoryPath]
                ?? indicators(for: docs)
            let newestDate = newestModificationDate(for: docs)
            return Group(
                id: directoryPath,
                displayName: displayNames[directoryPath] ?? directoryPath,
                directoryURL: dirURL,
                documents: docs,
                indicatorStates: indicatorStates,
                indicatorPulseToken: precomputedIndicatorPulseTokens?[directoryPath] ?? 0,
                newestModificationDate: newestDate,
                isPinned: pinnedGroupIDs.contains(directoryPath)
            )
        }

        var pinned: [Group] = []
        var unpinned: [Group] = []
        for group in groups {
            if group.isPinned { pinned.append(group) } else { unpinned.append(group) }
        }
        pinned = sorted(pinned, mode: sortMode)
        unpinned = sorted(unpinned, mode: sortMode)

        return .grouped(pinned + unpinned)
    }

    // MARK: - Internal (exposed for testability)

    static func indicators(
        for documents: [ReaderSidebarDocumentController.Document]
    ) -> [ReaderDocumentIndicatorState] {
        let states = documents.map { document in
            ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: document.readerStore.hasUnacknowledgedExternalChange,
                isCurrentFileMissing: document.readerStore.isCurrentFileMissing,
                unacknowledgedExternalChangeKind: document.readerStore.document.unacknowledgedExternalChangeKind
            )
        }

        return indicators(from: states)
    }

    static func indicators(
        from states: [ReaderDocumentIndicatorState]
    ) -> [ReaderDocumentIndicatorState] {
        var hasAdded = false
        var hasModified = false
        var hasDeleted = false

        for state in states {
            switch state {
            case .addedExternalChange:
                hasAdded = true
            case .externalChange:
                hasModified = true
            case .deletedExternalChange:
                hasDeleted = true
            case .none:
                break
            }
        }

        var result: [ReaderDocumentIndicatorState] = []
        if hasAdded {
            result.append(.addedExternalChange)
        }
        if hasModified {
            result.append(.externalChange)
        }
        if hasDeleted {
            result.append(.deletedExternalChange)
        }
        return result
    }

    // MARK: - Private

    private static func directoryURL(
        for document: ReaderSidebarDocumentController.Document
    ) -> URL? {
        document.readerStore.fileURL?.deletingLastPathComponent()
    }

    private static func newestModificationDate(
        for documents: [ReaderSidebarDocumentController.Document]
    ) -> Date? {
        documents.compactMap { document in
            document.readerStore.fileLastModifiedAt
                ?? document.readerStore.lastExternalChangeAt
                ?? document.readerStore.lastRefreshAt
        }.max()
    }

    private static func orderedUniqueDirectoryPaths(
        from documents: [ReaderSidebarDocumentController.Document]
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for document in documents {
            let path = directoryURL(for: document)?.path(percentEncoded: false) ?? ""
            if seen.insert(path).inserted {
                ordered.append(path)
            }
        }

        return ordered
    }

    private static func sorted(_ groups: [Group], mode: ReaderSidebarSortMode) -> [Group] {
        groups.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element

                switch mode {
                case .openOrder:
                    return lhs.offset < rhs.offset
                case .nameAscending:
                    let comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                    return lhs.offset < rhs.offset
                case .nameDescending:
                    let comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    if comparison != .orderedSame {
                        return comparison == .orderedDescending
                    }
                    return lhs.offset < rhs.offset
                case .lastChangedNewestFirst:
                    if let isOrderedByDate = isOrderedByDate(
                        lhs: left.newestModificationDate,
                        rhs: right.newestModificationDate,
                        newestFirst: true
                    ) {
                        return isOrderedByDate
                    }

                    let comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                    return lhs.offset < rhs.offset
                case .lastChangedOldestFirst:
                    if let isOrderedByDate = isOrderedByDate(
                        lhs: left.newestModificationDate,
                        rhs: right.newestModificationDate,
                        newestFirst: false
                    ) {
                        return isOrderedByDate
                    }

                    let comparison = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
                    if comparison != .orderedSame {
                        return comparison == .orderedAscending
                    }
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    private static func isOrderedByDate(lhs: Date?, rhs: Date?, newestFirst: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (leftDate?, rightDate?):
            guard leftDate != rightDate else {
                return nil
            }
            return newestFirst ? (leftDate > rightDate) : (leftDate < rightDate)
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    static func disambiguatedDisplayNames(
        for directoryPaths: [String]
    ) -> [String: String] {
        guard !directoryPaths.isEmpty else { return [:] }

        let nonEmpty = directoryPaths.filter { !$0.isEmpty }
        let untitled = directoryPaths.filter { $0.isEmpty }

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
            for (_, paths) in duplicateNames {
                for path in paths {
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
}
