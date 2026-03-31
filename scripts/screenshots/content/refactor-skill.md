# Skill: Refactor to Actor

## When to Use

When a `class` has mutable state accessed from multiple isolation contexts.

## Steps

1. Identify shared mutable state (`var` properties)
2. Check all access points via `swift_find_symbol_references`
3. Convert `class` to `actor`
4. Add `await` at all call sites
5. Run `swift_validate_file` to verify compilation
6. Update tests for async patterns

## Template

```swift
// BEFORE
class NetworkClient {
    var headers: [String: String] = [:]
    func request(_ endpoint: Endpoint) async throws -> Data { ... }
}

// AFTER
actor NetworkClient {
    private var headers: [String: String] = [:]
    func request(_ endpoint: Endpoint) async throws -> Data { ... }
}
```
