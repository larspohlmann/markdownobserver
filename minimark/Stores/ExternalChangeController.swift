import Foundation
import Observation

enum ExternalChangeKind: Equatable, Sendable {
    case added
    case modified
}

@MainActor
@Observable
final class ExternalChangeController {
    var lastExternalChangeAt: Date?
    var hasUnacknowledgedExternalChange: Bool = false
    var unacknowledgedExternalChangeKind: ExternalChangeKind = .modified

    @ObservationIgnored var onStateChanged: (() -> Void)?

    func noteObservedExternalChange(kind: ExternalChangeKind = .modified) {
        let previousKind = unacknowledgedExternalChangeKind
        let wasAcknowledged = !hasUnacknowledgedExternalChange
        lastExternalChangeAt = Date()
        hasUnacknowledgedExternalChange = true
        unacknowledgedExternalChangeKind = kind
        if wasAcknowledged || previousKind != kind {
            onStateChanged?()
        }
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
        onStateChanged = nil
    }
}
