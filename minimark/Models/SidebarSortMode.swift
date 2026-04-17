import Foundation

nonisolated enum SidebarSortMode: String, Codable, Sendable {
    case openOrder
    case nameAscending
    case nameDescending
    case lastChangedNewestFirst
    case lastChangedOldestFirst
    case manualOrder

    static let allCases: [SidebarSortMode] = [
        .openOrder,
        .nameAscending,
        .nameDescending,
        .lastChangedNewestFirst,
        .lastChangedOldestFirst
    ]

    static func availableCases(hasManualOrder: Bool) -> [SidebarSortMode] {
        hasManualOrder ? allCases + [.manualOrder] : allCases
    }

    var displayName: String {
        switch self {
        case .openOrder:
            return "Open Order"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .lastChangedNewestFirst:
            return "Last Changed Newest First"
        case .lastChangedOldestFirst:
            return "Last Changed Oldest First"
        case .manualOrder:
            return "Manual"
        }
    }

    var footerLabel: String {
        switch self {
        case .openOrder:
            return "Open Order"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .lastChangedNewestFirst:
            return "Newest First"
        case .lastChangedOldestFirst:
            return "Oldest First"
        case .manualOrder:
            return "Manual"
        }
    }

    func sorted<T>(_ values: [T], metadata: (T) -> ReaderSidebarSortDescriptor) -> [T] {
        values.enumerated()
            .sorted { lhs, rhs in
                let leftMetadata = metadata(lhs.element)
                let rightMetadata = metadata(rhs.element)
                return isOrderedBefore(
                    leftMetadata,
                    leftIndex: lhs.offset,
                    rightMetadata,
                    rightIndex: rhs.offset
                )
            }
            .map(\.element)
    }

    private func isOrderedBefore(
        _ lhs: ReaderSidebarSortDescriptor,
        leftIndex: Int,
        _ rhs: ReaderSidebarSortDescriptor,
        rightIndex: Int
    ) -> Bool {
        switch self {
        case .openOrder:
            return leftIndex < rightIndex
        case .nameAscending:
            return compareNames(lhs.displayName, rhs.displayName, ascending: true) ?? (leftIndex < rightIndex)
        case .nameDescending:
            return compareNames(lhs.displayName, rhs.displayName, ascending: false) ?? (leftIndex < rightIndex)
        case .lastChangedNewestFirst:
            return compareDates(lhs.lastChangedAt, rhs.lastChangedAt, newestFirst: true) ?? (leftIndex < rightIndex)
        case .lastChangedOldestFirst:
            return compareDates(lhs.lastChangedAt, rhs.lastChangedAt, newestFirst: false) ?? (leftIndex < rightIndex)
        case .manualOrder:
            return leftIndex < rightIndex
        }
    }

    private func compareNames(_ lhs: String?, _ rhs: String?, ascending: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
            guard comparison != .orderedSame else {
                return nil
            }

            if ascending {
                return comparison == .orderedAscending
            }

            return comparison == .orderedDescending
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }

    private func compareDates(_ lhs: Date?, _ rhs: Date?, newestFirst: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            guard lhs != rhs else {
                return nil
            }

            if newestFirst {
                return lhs > rhs
            }

            return lhs < rhs
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            return nil
        }
    }
}

nonisolated struct ReaderSidebarSortDescriptor: Sendable {
    let displayName: String?
    let lastChangedAt: Date?

    init(displayName: String?, lastChangedAt: Date?) {
        if let displayName, !displayName.isEmpty {
            self.displayName = displayName
        } else {
            self.displayName = nil
        }
        self.lastChangedAt = lastChangedAt
    }
}