import Foundation

@MainActor
enum SidebarGrouping: Equatable {
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
        sortMode: SidebarSortMode = .lastChangedNewestFirst,
        directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]? = nil,
        pinnedGroupIDs: Set<String> = [],
        precomputedIndicatorStates: [String: [ReaderDocumentIndicatorState]]? = nil,
        precomputedIndicatorPulseTokens: [String: Int]? = nil
    ) -> SidebarGrouping {
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

        let displayNames = PathDisambiguator.disambiguatedDisplayNames(for: Array(grouped.keys))

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
                hasUnacknowledgedExternalChange: document.readerStore.externalChange.hasUnacknowledgedExternalChange,
                isCurrentFileMissing: document.readerStore.document.isCurrentFileMissing,
                unacknowledgedExternalChangeKind: document.readerStore.externalChange.unacknowledgedExternalChangeKind
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
        document.readerStore.document.fileURL?.deletingLastPathComponent()
    }

    private static func newestModificationDate(
        for documents: [ReaderSidebarDocumentController.Document]
    ) -> Date? {
        documents.compactMap { document in
            document.readerStore.document.fileLastModifiedAt
                ?? document.readerStore.externalChange.lastExternalChangeAt
                ?? document.readerStore.renderingController.lastRefreshAt
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

    private static func sorted(_ groups: [Group], mode: SidebarSortMode) -> [Group] {
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
                case .manualOrder:
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

}
