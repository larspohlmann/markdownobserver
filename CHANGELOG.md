# Changelog

All notable changes to this project are documented in this file.

## [1.0.3] - 2026-03-24

### Added
- Added scalable include-subfolders flow support with selective exclusions for large folder trees.
- Added startup profiling hooks and expanded regression coverage for folder watch and sidebar flows.
- Added improved watcher-failure surfacing and recovery-path test coverage.

### Changed
- Improved folder watch startup responsiveness by caching scan results and reducing large-tree UI lag.
- Refined About window layout and repository link clarity.
- Set the subfolder depth limit to 5 to keep recursive watch behavior predictable.

### Fixed
- Prevented main-thread freezes during recursive folder watch startup.
- Fixed include-subfolders startup opening and folder selection default regressions.
- Preserved active file watching when document open flow fails.
- Improved handling for stale security bookmarks, initial scan failures, and path-log privacy.

### Chore
- Tuned Release Swift archive build settings.
- Advanced internal build number progression for release automation.

## [1.0.2] - 2026-03-22

### Added
- Added automated versioning and GitHub Release workflow support.
- Added author attribution and updated the About repository link.

### Changed
- Refactored reader flows to reduce coupling and improve maintainability.
- Fixed main-actor isolation in window callback configuration.

### Fixed
- Stabilized folder watch baseline age behavior.
- Added guard-path and deduplication test coverage for reader internals.
- Fixed flaky UI toggle test behavior.

### Chore
- Upgraded `upload-artifact` workflow action to v7.
- Ignored Xcode workspace user data files in repository tracking.

## [1.0.1] - 2026-03-21

### Added
- Added a streamlined PR review agent workflow for repository contribution checks.

### Changed
- Simplified app UI and internal logic composition to reduce complexity.
- Simplified action handling and view structure in the UI layer.
- Migrated legacy tabs settings and removed tab-mode specific infrastructure.

### Fixed
- Guarded recursive folder watch behavior against repeated open-event storms.
- Fixed watched-folder drag-open change ownership handling.
- Preserved watch options when starting folder watch sessions.
- Fixed hidden-path handling for folder watch operations.
- Avoided blank sidebar documents on watch-open failures.

### Chore
- Refined agent tooling and validation configuration.
- Added simplify skill support.