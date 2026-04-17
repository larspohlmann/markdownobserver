import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct BookmarkRefreshingTests {
    @Test @MainActor func returnsFallbackURLWhenNoBookmarkData() {
        var staleCalls = 0
        var failureCalls = 0
        let helper = BookmarkRefreshing(
            resolve: { _ in Issue.record("resolve should not be called"); return (URL(fileURLWithPath: "/x"), false) },
            create: { _ in Issue.record("create should not be called"); return Data() }
        )
        let fallback = URL(fileURLWithPath: "/tmp/fallback")

        let result = helper.resolveURL(
            bookmarkData: nil,
            fallbackURL: fallback,
            onStale: { _, _ in staleCalls += 1 },
            onFailure: { failureCalls += 1 }
        )

        #expect(result == fallback)
        #expect(staleCalls == 0)
        #expect(failureCalls == 0)
    }

    @Test @MainActor func returnsResolvedURLWhenBookmarkIsFresh() {
        let resolvedURL = URL(fileURLWithPath: "/tmp/resolved")
        var staleCalls = 0
        var failureCalls = 0
        var createCalls = 0
        let helper = BookmarkRefreshing(
            resolve: { _ in (resolvedURL, false) },
            create: { _ in createCalls += 1; return Data() }
        )

        let result = helper.resolveURL(
            bookmarkData: Data([0x01]),
            fallbackURL: URL(fileURLWithPath: "/tmp/fallback"),
            onStale: { _, _ in staleCalls += 1 },
            onFailure: { failureCalls += 1 }
        )

        #expect(result == resolvedURL)
        #expect(staleCalls == 0)
        #expect(failureCalls == 0)
        #expect(createCalls == 0)
    }

    @Test @MainActor func invokesOnStaleWithResolvedURLAndFreshBookmark() {
        let resolvedURL = URL(fileURLWithPath: "/tmp/resolved")
        let refreshedBookmark = Data([0x99, 0x88])
        var staleArgs: (URL, Data?)? = nil
        var failureCalls = 0
        let helper = BookmarkRefreshing(
            resolve: { _ in (resolvedURL, true) },
            create: { url in
                #expect(url == resolvedURL)
                return refreshedBookmark
            }
        )

        let result = helper.resolveURL(
            bookmarkData: Data([0x01]),
            fallbackURL: URL(fileURLWithPath: "/tmp/fallback"),
            onStale: { url, data in staleArgs = (url, data) },
            onFailure: { failureCalls += 1 }
        )

        #expect(result == resolvedURL)
        #expect(staleArgs?.0 == resolvedURL)
        #expect(staleArgs?.1 == refreshedBookmark)
        #expect(failureCalls == 0)
    }

    @Test @MainActor func invokesOnStaleWithNilBookmarkWhenCreationFails() {
        let resolvedURL = URL(fileURLWithPath: "/tmp/resolved")
        var staleArgs: (URL, Data?)? = nil
        let helper = BookmarkRefreshing(
            resolve: { _ in (resolvedURL, true) },
            create: { _ in throw NSError(domain: "test", code: 42) }
        )

        let result = helper.resolveURL(
            bookmarkData: Data([0x01]),
            fallbackURL: URL(fileURLWithPath: "/tmp/fallback"),
            onStale: { url, data in staleArgs = (url, data) },
            onFailure: {}
        )

        #expect(result == resolvedURL)
        #expect(staleArgs?.0 == resolvedURL)
        #expect(staleArgs?.1 == nil)
    }

    @Test @MainActor func invokesOnFailureWhenResolutionThrows() {
        let fallback = URL(fileURLWithPath: "/tmp/fallback")
        var failureCalls = 0
        var staleCalls = 0
        let helper = BookmarkRefreshing(
            resolve: { _ in throw NSError(domain: "test", code: 1) },
            create: { _ in Issue.record("create should not be called"); return Data() }
        )

        let result = helper.resolveURL(
            bookmarkData: Data([0x01]),
            fallbackURL: fallback,
            onStale: { _, _ in staleCalls += 1 },
            onFailure: { failureCalls += 1 }
        )

        #expect(result == fallback)
        #expect(failureCalls == 1)
        #expect(staleCalls == 0)
    }
}
