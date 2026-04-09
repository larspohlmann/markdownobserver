import Foundation
import Testing
@testable import minimark

struct ContentEmptyStateTests {
    @Test func noDocumentVariantShowsCorrectContent() {
        let variant = ContentEmptyStateView.Variant.noDocument
        switch variant {
        case .noDocument:
            // Expected path
            break
        case .folderWatchEmpty:
            Issue.record("Expected .noDocument variant")
        }
    }

    @Test func folderWatchEmptyVariantCarriesFolderName() {
        let variant = ContentEmptyStateView.Variant.folderWatchEmpty(folderName: "my-docs")
        switch variant {
        case .folderWatchEmpty(let name):
            #expect(name == "my-docs")
        case .noDocument:
            Issue.record("Expected .folderWatchEmpty variant")
        }
    }
}
