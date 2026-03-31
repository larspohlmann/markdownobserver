# PR #847 — Cache Actor Migration

## Summary

Converts `ImageCache` and `ResponseCache` from `class` to `actor`.

## Issues Found

### Missing `await` in test assertions

```swift
// ❌ Won't compile — actor-isolated property
func testEviction() {
    cache.set("a", data: largeData)
    XCTAssertEqual(cache.count, 1)
}

// ✅ Fixed
func testEviction() async {
    await cache.set("a", data: largeData)
    let count = await cache.count
    XCTAssertEqual(count, 1)
}
```

## Verdict

**Approve with minor changes.** Fix test `await` and add reentrancy comment.
