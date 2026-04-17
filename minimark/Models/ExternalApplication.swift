import Foundation

struct ExternalApplication: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL
}
