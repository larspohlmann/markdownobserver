# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build (debug, no signing required)
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build

# Run unit tests
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests

# Resolve Swift package dependencies
xcodebuild -resolvePackageDependencies -project minimark.xcodeproj -scheme minimark

# Clean build
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug clean
```

If Xcode MCP is configured for the session, prefer it for scheme-aware build and test work.

## Architecture

Native macOS app (SwiftUI + Combine). The shipped app name is **MarkdownObserver** — use that in user-visible copy, not "minimark" (which is the internal/repo identifier).

### Layer structure

- **Views** (`minimark/Views/`, `minimark/ContentView.swift`) — SwiftUI views. Keep business logic out of views.
- **Stores** (`minimark/Stores/`) — Observable state and coordination. Each store or controller owns a single responsibility (e.g. `ReaderSettingsStore` owns user settings, `WindowAppearanceController` owns window chrome, `SidebarGroupStateController` owns sidebar expand/collapse). `ReaderStore` holds per-document observable state and wires dependencies — it should not grow new responsibilities. Legacy coordination extensions exist under `Stores/Coordination/` but new behavior belongs in dedicated controllers or coordinators, not in more `ReaderStore` extensions.
- **Services** (`minimark/Services/`) — Focused business logic: markdown rendering, file/folder watching, security-scoped resource access, change diffing.
- **Models** (`minimark/Models/`) — Data types (themes, display modes, window seeds, etc.).
- **Support** (`minimark/Support/`) — Utilities: CSS generation, file routing, window registry, bundled assets, error types.

### Single external dependency

**Differ** (v1.4.6+) — used in `ChangedRegionDiffer` for tracking changed markdown regions.

## Conventions

- Preserve entitlements at `minimark/App/minimark.entitlements`.
- Prefer small, focused changes matching the existing layer split.
- Apply SOLID pragmatically — keep responsibilities narrow, avoid god objects. When adding behavior, create a new controller or coordinator with a single responsibility rather than extending an existing store.
- When incremental changes start to bloat a type or blur responsibilities, suggest a focused refactoring instead of layering more patches.
- Do not add new `ReaderStore` extensions. Extract new behavior into a standalone type that ReaderStore can delegate to or that views can observe independently.
- Internal APIs are allowed to change when it leads to better architecture. Do not treat internal type signatures as immutable — refactor them alongside their callers when the result is cleaner.
- Preserve public behavior and APIs unless the task explicitly calls for refactoring.
- Use targeted tests instead of broad suite changes when only a small behavior changed.

## Tests

Tests live in `minimarkTests/` grouped by domain: `Core/`, `ReaderStore/`, `Rendering/`, `Sidebar/`, `FolderWatch/`, `Infrastructure/`. Test doubles are in `TestSupport/`. UI tests are in `minimarkUITests/`.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on `macOS-latest`: resolve packages → build-for-testing → run unit tests. Code signing is disabled for CI.



