# Changelog

All notable changes to this project are documented in this file.

## [1.1.0] - 2026-03-31

### Added
- Added folder watch favorites with subfolder detail in info popover.
- Added sidebar subfolder grouping with collapsible sections and pinning.
- Added independent group and file sorting controls in sidebar.
- Added file selection dialog when watched folder contains many files.
- Added local image support via contextual folder access grant and data URI resolution.
- Added multi-file open and window-local drop routing.
- Added folder drop watch flow with blocked overlay for drag-and-drop directory watching.
- Added close action for sidebar groups.
- Added preserve-open-files behavior for favorites, skipping the initial prompt on reopen.
- Added product website with deploy workflow.

### Changed
- Redesigned top bar with layered layout, breadcrumb path, and watch strip.
- Redesigned sidebar grouping with toolbar, compact rows, and frosted headers.
- Redesigned sidebar filegroup headers for better visual hierarchy.
- Redesigned gutter change indicators with tinted pill design.
- Redesigned folder watch dialog for clarity and compactness.
- Redesigned exclusion dialog with progress ring and toggle switches.
- Redesigned Edit Favorites and Save Favorite dialogs.
- Removed content status bar and moved watch details to top strip.
- Migrated project to Xcode 16 synchronized groups.

### Fixed
- Fixed gutter positions not updating when expanded comparison panel shifts content.
- Fixed unreadable disabled button text in Watch Folder dialogs in light mode.
- Fixed leftover Untitled document when file selection dialog opens files.
- Fixed favorite dropdown text inheriting watching tint color.
- Fixed file selection dialog triggering on live auto-open.
- Fixed toolbar button text wrapping on narrow windows.
- Fixed safe unwrap for empty file picker and normalized URLs in window-local open.

### Chore
- Removed verbose security scope debug logging from folder watch flow.
- Optimized drag-drop directory checks on hot path.
- Refreshed feature list and build guidance documentation.
- Automated App Store screenshot capture pipeline.

## [1.0.4] - 2026-03-26

### Changed
- Refactored codebase for improved SOLID compliance with protocol-based service abstractions and dependency injection.
- Raised folder watch optimization threshold to 256 for better large-folder performance.
- Simplified folder watch UI and refined toolbar watch button.
- Post-diagnostic CPU optimizations and diagnostic workflow hardening.
- Reduced idle CPU usage for recursive folder watch.

### Fixed
- Guarded `nonisolated deinit` behind compiler version check for CI compatibility.
- Stabilized recursive watch timer assertion.
- Hardened diagnostics script and duplicate-key handling.

### Chore
- Ignored Claude and MCP configuration files in repository tracking.
- Advanced internal build number progression.

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