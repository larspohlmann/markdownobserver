import SwiftUI

struct ContentUtilityRailView: View {
    let state: ContentUtilityRailState
    @Binding var isTOCVisible: Bool
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onStartSourceEditing: () -> Void

    var body: some View {
        ContentUtilityRail(
            hasFile: state.hasFile,
            documentViewMode: state.documentViewMode,
            showEditButton: state.showEditButton,
            canStartSourceEditing: state.canStartSourceEditing,
            onSetDocumentViewMode: onSetDocumentViewMode,
            onStartSourceEditing: onStartSourceEditing,
            hasTOCHeadings: state.hasTOCHeadings,
            isTOCVisible: $isTOCVisible
        )
    }
}
