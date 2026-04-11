# Changelog

All notable changes to this project are documented in this file.

## [1.2.3] - 2026-04-11

### Security
- Added Content Security Policy meta tags to reader and comparison views.
- Removed file:// from safe URL schemes; bundled scripts and https images are allowlisted explicitly.

### Changed
- Split ReaderDocumentState into concern-based structs for clearer responsibility boundaries.

### Fixed
- Fixed TOC button visible in split and source view modes.
- Fixed deleted files appearing in sidebar when opening a favorite.
- Fixed scroll-sync bounce-back during change navigation.
- Fixed overlay-aware top padding in source view.
- Fixed change highlights showing at wrong line inside code blocks.

### Performance
- Added dictionary index for O(1) document-by-URL lookup.
- Eliminated redundant URL normalizations and deduplicated watch-applies hot path.
- Optimized watchedDocumentIDs and stopWatchingFolders with cached URLs.
- Used adaptive timestamp intervals in sidebar rows.

## [1.2.2] - 2026-04-10

### Added
- Added manual sidebar group reorder with drag-and-drop.
- Added dock icon indicators for created/modified/deleted change counts.
- Added edit subfolders button to the watch pill for quick subfolder management.
- Added styled empty state for the content area.
- Added first-use hint popover bubbles for discoverability.

### Changed
- Replaced DispatchSource folder watching with FSEvents for better large-tree performance.
- Coalesced adjacent changed regions into single consolidated changes.
- Improved change pill navigation with wrap-around and always-active buttons.
- Polished sidebar chrome: close button scale, selection highlight, chevron rotation, multi-select badge, sticky headers, and drag feedback.
- Polished hover feedback for sidebar, TOC, and pill controls.
- Polished tooltips and first-use hints presentation.
- Highlighted TOC button while its popover is open.
- Narrowed TimelineView scope from sidebar list to individual document row timestamps.
- Simplified notification event model.

### Fixed
- Fixed top bar text unreadable in empty state with opposing theme color schemes.
- Fixed dock badge not updating on change-kind transition.
- Fixed manual group order lost when switching sort modes.
- Fixed redundant sidebar row state derivation.

## [1.2.1] - 2026-04-07

### Changed
- Refined sidebar external change indicators with pulse feedback and native system colors.
- Removed syntax theme color coupling from native UI; syntax palette now only feeds HTML and settings preview.

### Fixed
- Fixed overlay inset alignment so status warnings and navigation targets offset correctly below the top bar.

## [1.2.0] - 2026-04-06

### Added
- Added Table of Contents overlay for quick section navigation.
- Added native titlebar integration for watch button and sidebar toggle.
- Added Amber Terminal, Green Terminal, and Green Terminal (Static) themes with CRT effects.
- Added Newspaper, Focus, Commodore 64, and Game Boy themes.
- Added per-favorite locked appearance for themes and font size.
- Added per-favorite workspace state preserving sidebar width, sort mode, and group state.
- Added deferred document loading for large watched folders.
- Added loading spinner overlay for deferred document materialization.
- Added diff baseline lookback setting with presets in Settings UI.
- Added sidebar footer with scan progress and file count.
- Added two-phase folder scan startup for faster initial responsiveness.
- Added animated sidebar group expand/collapse.
- Added floating content utility rail and change-navigation pill overlays.
- Added auto-discovery of new files when opening favorites.
- Added custom rounded checkbox design.
- Added window width adjustment when sidebar appears or hides.

### Changed
- Restyled change-navigation pill to match watching pill.
- Moved actions dropdown from content utility rail to topbar.
- Changed default window aspect ratio from golden ratio to US Letter.
- Migrated ReaderStore and ReaderWindowRootView to @Observable.
- Migrated sidebar group state to dedicated controller for fast expand/sort/pin.
- Refactored codebase through multi-phase coupling reduction, god object splits, and value type extractions.
- Introduced FileOpenCoordinator to fix multi-file drop race condition.

### Fixed
- Fixed table cells shrinking below readable width.
- Fixed change indicator not showing for live auto-opened files.
- Fixed auto-select of newest file when opening a favorite.
- Fixed sidebar width not restoring from favorite when sidebar re-appears.
- Fixed stale toggle binding in folder exclusion dialog.
- Fixed locked appearance not propagating to new documents in favorites.
- Fixed UI freezes when changing theme or font size settings.
- Fixed sidebar header toolbar clipping at narrow widths.
- Fixed change navigation counter starting at wrong value before first jump.
- Fixed diff baseline tracker not seeding on auto-open.
- Fixed favorites intermittently losing locked theme on reopen.
- Fixed scanning progress bar not visible when opening favorites.
- Fixed sidebar width changing during window resize.
- Fixed sidebar width growing on each favorite reopen.
- Fixed deferred documents not showing change indicator on external change.
- Fixed content utility rail visible when no file is open.

### Performance
- Extracted ContentViewAdapter to narrow observation scope.
- Batched favorites persistence onChange cascade.
- Fixed sidebar resize sluggishness with many files.
- Fixed 80-second scan delay when opening favorites.

### Chore
- Automated App Store screenshot capture with real-project content and theme switching.

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