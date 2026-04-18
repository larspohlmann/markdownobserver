import SwiftUI

extension AnyTransition {
    static let overlayPill: AnyTransition = .asymmetric(
        insertion: .opacity.combined(with: .move(edge: .top)),
        removal: .opacity
    )
}
