# Changelog

All notable changes to this project are documented in this file.

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