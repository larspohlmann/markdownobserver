import Foundation
import Testing
@testable import minimark

struct ContentEmptyStateTests {
    @Test func noDocumentVariantIsEquatable() {
        let variant = ContentEmptyStateView.Variant.noDocument
        #expect(variant == .noDocument)
    }

    @Test func folderWatchEmptyVariantCarriesFolderName() {
        let variant = ContentEmptyStateView.Variant.folderWatchEmpty(folderName: "my-docs")
        #expect(variant == .folderWatchEmpty(folderName: "my-docs"))
    }

    @Test func folderWatchEmptyVariantDistinguishesFolderNames() {
        let a = ContentEmptyStateView.Variant.folderWatchEmpty(folderName: "docs")
        let b = ContentEmptyStateView.Variant.folderWatchEmpty(folderName: "notes")
        #expect(a != b)
    }

    @Test func variantsAreDistinct() {
        let noDoc = ContentEmptyStateView.Variant.noDocument
        let watchEmpty = ContentEmptyStateView.Variant.folderWatchEmpty(folderName: "test")
        #expect(noDoc != watchEmpty)
    }
}
