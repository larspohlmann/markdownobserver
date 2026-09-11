import Foundation

/// What the user asked for from the status bar menu.
enum DiffBaselineSelection: Equatable, Sendable {
    case automatic
    case snapshot(DiffBaselineSnapshot.ID)
}

/// How the comparison baseline is chosen for the current document.
enum DiffBaselineSelectionMode: Equatable, Sendable {
    case automatic
    case pinned(DiffBaselineSnapshot.ID)
}
