import Foundation
import Testing
@testable import minimark

@Suite
struct SecurityScopedBookmarkResolverTests {

    @Test func returnsFallbackWhenBookmarkDataIsNil() {
        let fallback = URL(fileURLWithPath: "/some/fallback.md")
        let resolved = SecurityScopedBookmarkResolver.resolveSecurityScopedBookmark(nil, fallbackURL: fallback)

        #expect(resolved == fallback)
    }

    @Test func returnsFallbackWhenBookmarkDataIsInvalid() {
        let fallback = URL(fileURLWithPath: "/some/fallback.md")
        let invalidData = Data("not a bookmark".utf8)
        let resolved = SecurityScopedBookmarkResolver.resolveSecurityScopedBookmark(invalidData, fallbackURL: fallback)

        #expect(resolved == fallback)
    }
}
