import Testing
import WebKit
@testable import minimark

@Suite(.serialized)
struct WebKitWarmupTests {
    @Test @MainActor func processPoolIsNilBeforeWarmup() {
        let warmup = WebKitWarmup()
        #expect(warmup.processPool == nil)
    }

    @Test @MainActor func warmUpCreatesProcessPool() {
        let warmup = WebKitWarmup()
        warmup.warmUp()
        #expect(warmup.processPool != nil)
    }

    @Test @MainActor func warmUpIsIdempotent() {
        let warmup = WebKitWarmup()
        warmup.warmUp()
        let firstPool = warmup.processPool
        warmup.warmUp()
        #expect(warmup.processPool === firstPool)
    }
}
