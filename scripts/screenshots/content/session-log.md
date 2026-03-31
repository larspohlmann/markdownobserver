# Agent Session — March 29

## Completed

- [x] Analyze `NetworkClient` for thread safety issues
- [x] Convert `ImageCache` from `class` to `actor`
- [x] Add `@MainActor` to all ViewModel `updateUI()` methods
- [x] Write unit tests for `TokenBucket` rate limiter
- [x] Remove dead code: `LegacyPushManager` (unused since v3.2)

## In Progress

- [ ] Refactor `APIRouter` — extract into `Endpoint` enum
- [ ] Add structured concurrency to `SyncCoordinator`

## Remaining

- [ ] Audit 7 `@unchecked Sendable` conformances
- [ ] Replace `DispatchQueue.global()` with `Task {}` (5 remaining)
- [ ] Update `Package.swift` for strict concurrency

## Notes

> Found 23 data race warnings after enabling strict checking.
> `ImageCache` was highest risk: `NSCache` with concurrent read/write
> from `URLSession` delegate callbacks. Converted to `actor`.
