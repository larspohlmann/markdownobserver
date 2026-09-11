import Foundation

/// One recorded prior version of a file's markdown, used as a diff baseline.
struct DiffBaselineSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let markdown: String
    let capturedAt: Date

    init(id: UUID = UUID(), markdown: String, capturedAt: Date) {
        self.id = id
        self.markdown = markdown
        self.capturedAt = capturedAt
    }
}
