# Letter-Format Window Sizing with Sidebar-Aware Resizing

**Issue:** [#62](https://github.com/larspohlmann/markdownobserver/issues/62)
**Date:** 2026-04-02

## Goal

The default window size should give the content area a US Letter aspect ratio (8.5:11). When the sidebar becomes visible, the window widens so the content area retains that ratio. When the sidebar hides, the window shrinks back.

## Design

### 1. Change aspect ratio in ReaderWindowDefaults

Replace the golden ratio (1.618) with the US Letter ratio (11/8.5 = 1.2941).

- `letterAspectRatio = 11.0 / 8.5` (rename from `goldenRatio`)
- `baseWidth` stays at 1100 (good fit for large screens)
- `baseHeight` becomes `1100 * 1.2941 = ~1424` (down from ~1780)

The existing `fittedSize` logic already scales proportionally to fit the screen's visible frame, so small screens are handled automatically.

### 2. Sidebar-aware window resizing

When the sidebar becomes visible or hidden, adjust the window width so the content area keeps its aspect ratio.

**Where:** `ReaderWindowRootView`, which already manages `sidebarWidth` as `@State` and knows when the sidebar is visible.

**Mechanism:**
- Detect sidebar visibility changes (the view already tracks this via the sidebar document controller state)
- On sidebar show: find the hosting `NSWindow` and widen it by `sidebarWidth` + the divider width
- On sidebar hide: narrow the window by the same amount
- Clamp to screen bounds: if the widened frame would exceed the screen's visible frame, clamp to screen width (content area shrinks as fallback)
- Use `NSWindow.setFrame(_:display:animate:)` with `animate: true` for a smooth transition
- Anchor the resize to the window's current leading edge (expand rightward); if that would go off-screen, expand leftward instead

**NSWindow access:** Use a small `NSViewRepresentable` (or the existing window accessor pattern in the codebase) to get a reference to the hosting `NSWindow` from the SwiftUI view hierarchy. Check if such a helper already exists; if not, add a minimal one.

### 3. Edge cases

- **Window already manually resized by user:** Still apply the delta (add/remove sidebar width). The user's chosen content width is preserved.
- **Screen too narrow for sidebar + content:** Clamp to screen width. The content area shrinks — same as current behavior.
- **Multiple displays:** `NSWindow.screen` gives the correct screen for the window's current position. Use its `visibleFrame` for clamping.
- **Sidebar width changes (drag to resize):** Only adjust window width on show/hide transitions, not on continuous sidebar drag. The user is in control during drag.

### 4. Update ReaderHostedWindowController

The UI-test window controller also references `ReaderWindowDefaults.defaultWidth/Height`. It gets the new dimensions automatically since it reads from the same constants.

### 5. Update tests

- Update existing `ReaderWindowDefaults` tests: replace `goldenRatio` references with `letterAspectRatio`, adjust expected values
- Add a test for the sidebar resize delta calculation (pure logic, no NSWindow needed)

## Files to change

| File | Change |
|------|--------|
| `minimark/Support/ReaderWindowDefaults.swift` | Replace golden ratio with letter ratio |
| `minimark/Views/ReaderWindowRootView.swift` | Add sidebar-aware window resizing on show/hide |
| `minimarkTests/Core/ReaderSettingsAndModelsTests.swift` | Update existing window default tests |

## Out of scope

- Changing sidebar width defaults
- Persisting user-resized window dimensions
- Changing the Settings or About window sizes
