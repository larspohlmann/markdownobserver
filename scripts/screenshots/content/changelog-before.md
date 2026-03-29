# Changelog

## v4.2.0 — 2026-03-15

### Added
- Pipeline health monitoring via `HealthCheck` protocol
- Automatic retry with exponential backoff

### Changed
- Default buffer size increased from 512 to 1024

### Deprecated
- `Pipeline.observe()` — use `Pipeline.subscribe()` instead

### Fixed
- Memory leak in long-running `merge` operations
- Race condition in concurrent subscriber joins
