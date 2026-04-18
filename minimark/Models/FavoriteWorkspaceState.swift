import Foundation

nonisolated struct FavoriteWorkspaceState: Equatable, Hashable, Codable, Sendable {
    static let defaultSidebarWidth: CGFloat = 250

    var fileSortMode: SidebarSortMode
    var groupSortMode: SidebarSortMode
    var sidebarPosition: MultiFileDisplayMode
    var sidebarWidth: CGFloat
    var pinnedGroupIDs: Set<String>
    var collapsedGroupIDs: Set<String>
    var lockedAppearance: LockedAppearance? = nil
    var manualGroupOrder: [String]? = nil

    private enum CodingKeys: String, CodingKey {
        case fileSortMode
        case groupSortMode
        case sidebarPosition
        case sidebarWidth
        case pinnedGroupIDs
        case collapsedGroupIDs
        case lockedAppearance
        case manualGroupOrder
    }

    init(
        fileSortMode: SidebarSortMode,
        groupSortMode: SidebarSortMode,
        sidebarPosition: MultiFileDisplayMode,
        sidebarWidth: CGFloat,
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        lockedAppearance: LockedAppearance? = nil,
        manualGroupOrder: [String]? = nil
    ) {
        self.fileSortMode = fileSortMode
        self.groupSortMode = groupSortMode
        self.sidebarPosition = sidebarPosition
        self.sidebarWidth = sidebarWidth
        self.pinnedGroupIDs = pinnedGroupIDs
        self.collapsedGroupIDs = collapsedGroupIDs
        self.lockedAppearance = lockedAppearance
        self.manualGroupOrder = manualGroupOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileSortMode = try container.decode(SidebarSortMode.self, forKey: .fileSortMode)
        groupSortMode = try container.decode(SidebarSortMode.self, forKey: .groupSortMode)
        sidebarPosition = try container.decode(MultiFileDisplayMode.self, forKey: .sidebarPosition)
        sidebarWidth = try container.decode(CGFloat.self, forKey: .sidebarWidth)
        pinnedGroupIDs = try container.decode(Set<String>.self, forKey: .pinnedGroupIDs)
        collapsedGroupIDs = try container.decode(Set<String>.self, forKey: .collapsedGroupIDs)
        lockedAppearance = try container.decodeIfPresent(LockedAppearance.self, forKey: .lockedAppearance)
        manualGroupOrder = try container.decodeIfPresent([String].self, forKey: .manualGroupOrder)
    }

    static func from(
        settings: Settings,
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        sidebarWidth: CGFloat
    ) -> FavoriteWorkspaceState {
        FavoriteWorkspaceState(
            fileSortMode: settings.sidebarSortMode,
            groupSortMode: settings.sidebarGroupSortMode,
            sidebarPosition: settings.multiFileDisplayMode,
            sidebarWidth: sidebarWidth,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs,
            manualGroupOrder: nil
        )
    }
}
