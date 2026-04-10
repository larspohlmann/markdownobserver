import Foundation

nonisolated enum FirstUseHint: String, Codable, CaseIterable, Sendable {
    case manualGroupReorder
    case multiSelect
    case changeNavigation
}
