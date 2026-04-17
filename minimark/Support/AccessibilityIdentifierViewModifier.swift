import SwiftUI

extension View {
    func accessibilityIdentifier(_ id: ReaderAccessibilityID) -> some View {
        accessibilityIdentifier(id.rawValue)
    }
}
