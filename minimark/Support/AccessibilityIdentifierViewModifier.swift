import SwiftUI

extension View {
    func accessibilityIdentifier(_ id: AccessibilityID) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
