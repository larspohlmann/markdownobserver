import SwiftUI

struct ContentUtilityRailView: View {
    let state: ContentUtilityRailState
    @Binding var isTOCVisible: Bool
    let onSetDocumentViewMode: (DocumentViewMode) -> Void
    let onStartSourceEditing: () -> Void

    var body: some View {
        ContentUtilityRail(
            state: state,
            onSetDocumentViewMode: onSetDocumentViewMode,
            onStartSourceEditing: onStartSourceEditing,
            isTOCVisible: $isTOCVisible
        )
    }
}
