import Foundation

struct ReaderExternalApplication: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let bundleURL: URL
}
