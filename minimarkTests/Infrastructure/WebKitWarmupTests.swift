import Testing
import WebKit
@testable import minimark

@Suite(.serialized)
struct WebKitWarmupTests {
    @Test @MainActor func hasNotWarmedUpBeforeWarmup() {
        let warmup = WebKitWarmup()
        #expect(!warmup.hasWarmedUp)
    }

    @Test @MainActor func warmUpSetsFlag() {
        let warmup = WebKitWarmup()
        warmup.warmUp()
        #expect(warmup.hasWarmedUp)
    }

    @Test @MainActor func warmUpIsIdempotent() {
        let warmup = WebKitWarmup()
        warmup.warmUp()
        warmup.warmUp()
        #expect(warmup.hasWarmedUp)
    }
}
