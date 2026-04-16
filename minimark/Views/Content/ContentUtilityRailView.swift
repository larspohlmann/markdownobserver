import SwiftUI

struct ContentUtilityRailView: View {
    let hasFile: Bool
    let documentViewMode: ReaderDocumentViewMode
    let showEditButton: Bool
    let canStartSourceEditing: Bool
    let hasTOCHeadings: Bool
    @Binding var isTOCVisible: Bool
    let onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void
    let onStartSourceEditing: () -> Void

    var body: some View {
        ContentUtilityRail(
            hasFile: hasFile,
            documentViewMode: documentViewMode,
            showEditButton: showEditButton,
            canStartSourceEditing: canStartSourceEditing,
            onSetDocumentViewMode: onSetDocumentViewMode,
            onStartSourceEditing: onStartSourceEditing,
            hasTOCHeadings: hasTOCHeadings,
            isTOCVisible: $isTOCVisible
        )
    }
}
