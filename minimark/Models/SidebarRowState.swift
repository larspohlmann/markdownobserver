import Foundation

struct SidebarRowState: Equatable, Identifiable {
    let id: UUID
    let title: String
    let lastModified: Date?
    let isFileMissing: Bool
    let indicatorState: ReaderDocumentIndicatorState
}
