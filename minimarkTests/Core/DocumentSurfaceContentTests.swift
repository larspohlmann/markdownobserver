import Testing
@testable import minimark

struct DocumentSurfaceContentTests {
    @Test
    func loadingCasePreservesOverlayState() {
        let overlay = LoadingOverlayState(headline: "Loading\u{2026}", subtitle: "Parsing")
        let content: DocumentSurfaceContent = .loading(overlay)

        guard case .loading(let payload) = content else {
            Issue.record("expected .loading")
            return
        }
        #expect(payload.headline == "Loading\u{2026}")
        #expect(payload.subtitle == "Parsing")
    }

    @Test
    func emptyCasePreservesVariant() {
        let variant: ContentEmptyStateView.Variant = .noDocument
        let content: DocumentSurfaceContent = .empty(variant)

        guard case .empty(let payload) = content else {
            Issue.record("expected .empty")
            return
        }
        #expect(payload == variant)
    }

    @Test
    func documentCasePreservesViewMode() {
        let content: DocumentSurfaceContent = .document(.split)

        guard case .document(let mode) = content else {
            Issue.record("expected .document")
            return
        }
        #expect(mode == .split)
    }
}
