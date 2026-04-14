import Foundation
import Testing
@testable import minimark

@Suite
struct BookmarkResolverTests {

    @Test func returnsFallbackWhenBookmarkDataIsNil() {
        let fallback = URL(fileURLWithPath: "/some/fallback.md")
        let resolved = BookmarkResolver.resolveSecurityScopedBookmark(nil, fallbackURL: fallback)

        #expect(resolved == fallback)
    }

    @Test func returnsFallbackWhenBookmarkDataIsInvalid() {
        let fallback = URL(fileURLWithPath: "/some/fallback.md")
        let invalidData = Data("not a bookmark".utf8)
        let resolved = BookmarkResolver.resolveSecurityScopedBookmark(invalidData, fallbackURL: fallback)

        #expect(resolved == fallback)
    }
}
