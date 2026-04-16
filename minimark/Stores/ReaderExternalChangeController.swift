import Foundation
import Observation

enum ReaderExternalChangeKind: Equatable, Sendable {
    case added
    case modified
}

@MainActor
@Observable
final class ReaderExternalChangeController {
    var lastExternalChangeAt: Date?
    var hasUnacknowledgedExternalChange: Bool = false
    var unacknowledgedExternalChangeKind: ReaderExternalChangeKind = .modified

    @ObservationIgnored var onExternalChangeKindChanged: (() -> Void)?
    @ObservationIgnored var onStateChanged: (() -> Void)?

    func noteObservedExternalChange(kind: ReaderExternalChangeKind = .modified) {
        let previousKind = unacknowledgedExternalChangeKind
        let wasAcknowledged = !hasUnacknowledgedExternalChange
        lastExternalChangeAt = Date()
        hasUnacknowledgedExternalChange = true
        unacknowledgedExternalChangeKind = kind
        if !wasAcknowledged && previousKind != kind {
            onExternalChangeKindChanged?()
        }
        onStateChanged?()
    }

    func clear() {
        let wasUnacknowledged = hasUnacknowledgedExternalChange
        hasUnacknowledgedExternalChange = false
        unacknowledgedExternalChangeKind = .modified
        if wasUnacknowledged {
            onStateChanged?()
        }
    }

    func reset() {
        lastExternalChangeAt = nil
        hasUnacknowledgedExternalChange = false
        unacknowledgedExternalChangeKind = .modified
        onExternalChangeKindChanged = nil
        onStateChanged = nil
    }
}
