# Changelog

## v4.3.0 — 2026-03-29

### Added
- `@AgentTool` macro for declarative tool registration
- Built-in rate limiting for API-backed tools
- Structured logging via `os.Logger` with subsystem tags

### Fixed
- Token refresh deadlock when multiple tools request auth simultaneously

## v4.2.0 — 2026-03-15

### Added
- Pipeline health monitoring via `HealthCheck` protocol
- Automatic retry with configurable backoff strategy

### Changed
- Default buffer size increased from 512 to 2048

### Fixed
- Memory leak in long-running `merge` operations
- Race condition in concurrent subscriber joins
