import Foundation

nonisolated enum MultiFileDisplayMode: String, CaseIterable, Codable, Sendable {
    case sidebarLeft
    case sidebarRight

    nonisolated enum SidebarPlacement: Sendable {
        case left
        case right
    }

    var displayName: String {
        switch self {
        case .sidebarLeft:
            return "Sidebar Left"
        case .sidebarRight:
            return "Sidebar Right"
        }
    }

    var secondaryActionLabel: String {
        "Open Markdown in Sidebar..."
    }

    var usesSidebarLayout: Bool {
        true
    }

    var sidebarPlacement: SidebarPlacement {
        switch self {
        case .sidebarLeft:
            return .left
        case .sidebarRight:
            return .right
        }
    }

    var toggledSidebarPlacementMode: MultiFileDisplayMode {
        switch self {
        case .sidebarLeft:
            return .sidebarRight
        case .sidebarRight:
            return .sidebarLeft
        }
    }

    func requiresRestart(from launchedMode: MultiFileDisplayMode) -> Bool {
        false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case Self.sidebarLeft.rawValue, "sidebar", "tabs":
            self = .sidebarLeft
        case Self.sidebarRight.rawValue:
            self = .sidebarRight
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown MultiFileDisplayMode raw value: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}