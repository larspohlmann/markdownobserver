# Top Bar Redesign — Compact Icon Rail (4A)

**Issue:** [#67 — Redesign top bar — reduce visual clutter and improve layout](https://github.com/larspohlmann/markdownobserver/issues/67)

## Problem

When all conditional elements are visible (folder watch active + changes detected + source editing enabled), the top bar is packed. The breadcrumb/document context, change navigation, view mode switch, and actions menu all compete for horizontal space on a single row.

## Solution

Move secondary controls (view mode, change navigation, edit, actions) from the top bar into a new **sticky right-side utility rail** (44px wide). The top bar becomes a clean, spacious document context bar.

## Layout

### Top Bar (remains)

```
┌─────────────────────────────────────────────────────┐
│  [🔭 Watching ▼]     README.md                      │  44px — main bar
│                       ~/Projects › docs · 2m ago     │
├─────────────────────────────────────────────────────┤
│  ⓘ  WATCHING  ~/Projects/docs  [2 filtered]  ★  ■  │  30px — watch strip (conditional)
├─────────────────────────────────────────────────────┤
│  ✎ Editing source with unsaved changes   [Save] [X] │  editing banner (conditional)
└─────────────────────────────────────────────────────┘
```

**Main bar contents (left to right):**
1. `FolderWatchToolbarButton` — binoculars with text ("Watch Folder" / "Watching") + dropdown chevron. Unchanged.
2. Spacer (16px)
3. `BreadcrumbDocumentContext` — document title + breadcrumb path + timestamp. Unchanged, fills remaining space.

**Removed from main bar:** `ChangeNavigationControls`, `SourceEditingControls`, `DocumentViewModeSwitch`, `OpenInMenuButton`.

**Watch strip:** Unchanged — conditional, green-tinted, shows when folder watch is active.

**Source editing banner:** Unchanged — conditional, shows when source editing is active.

### Utility Rail (new)

```
     ┌──────┐
     │  ◉   │  Preview (active)
     │  ▥   │  Split
     │  ☰   │  Source
     │──────│
     │  ↑   │  Previous change    ← conditional
     │  ↓   │  Next change        ← conditional
     │──────│
     │  ✎   │  Edit source        ← conditional
     │──────│
     │  ⋯   │  Actions menu
     └──────┘
```

**Placement:** Right edge of the content area, below the top bar (including watch strip and editing banner). Full height of the content area. Sticky — does not scroll with content.

**Width:** 44px total (32px button + 6px padding each side).

**Button specs:**
- Size: 32x32px, corner radius 8px
- Background: `Color.primary.opacity(0.06)` with `Color.primary.opacity(0.10)` border (1px)
- Active state (view mode): purple accent (`accent-purple-bg`, `accent-purple-border`)
- Icon: SF Symbols, 12px semibold
- Spacing between buttons: 6px
- Group separators: 1px line, 20px wide, `Color.primary.opacity(0.08)`

**Rail background:** `.regularMaterial` — matches the top bar. Left border: 1px `Color.primary.opacity(0.10)`.

**Tooltips:** Every button gets a native `.help()` tooltip:
- Preview / Split View / Source
- Previous Change / Next Change
- Edit Source
- Actions

### Conditional Visibility in the Rail

| Element | Visible when |
|---------|-------------|
| View mode (3 buttons) | Always |
| Change navigation (2 buttons) | `canNavigateChangedRegions == true` |
| Edit button | `showSourceEditingControls == true && !isSourceEditing` |
| Actions menu | Always |

Separators between groups only render when both adjacent groups are visible.

## Architecture

### New View: `ContentUtilityRail`

A new SwiftUI view in `minimark/Views/Content/`. Receives the same action callbacks and state that `ReaderTopBar` currently uses for these controls.

**Properties:**
- `documentViewMode: ReaderDocumentViewMode`
- `hasFile: Bool`
- `showSourceEditingControls: Bool`
- `isSourceEditing: Bool`
- `canNavigateChangedRegions: Bool`
- `onNavigateChangedRegion: (ReaderChangedRegionNavigationDirection) -> Void`
- `onSetDocumentViewMode: (ReaderDocumentViewMode) -> Void`
- `onStartSourceEditing: () -> Void`
- `apps: [ReaderExternalApplication]` (for actions menu)
- Plus all the action callbacks currently on `OpenInMenuButton`

### Modified View: `ReaderTopBar`

Remove from the main bar `HStack`:
- `ChangeNavigationControls`
- `SourceEditingControls`
- `DocumentViewModeSwitch`
- `OpenInMenuButton`

The trailing `HStack(spacing: Metrics.trailingControlSpacing)` block is removed entirely. The main bar simplifies to: watch button + spacer + breadcrumb.

### Modified Layout: Parent Content View

The parent that currently renders `ReaderTopBar` above the content `WebView` needs to place the rail. The layout becomes:

```
VStack(spacing: 0) {
    ReaderTopBar(...)           // simplified
    HStack(spacing: 0) {
        WebView(...)            // existing content, fills remaining space
        ContentUtilityRail(...) // new, fixed 44px width
    }
}
```

### Moved Components

These private structs move from `ReaderTopBar.swift` to `ContentUtilityRail.swift`, adapted for vertical layout:
- `ChangeNavigationControls` — arrows become vertical stack
- `DocumentViewModeSwitch` — segmented control becomes vertical button group
- `SourceEditingControls` — becomes a single icon button
- `OpenInMenuButton` — stays as-is (NSViewRepresentable), just repositioned

## What Does NOT Change

- `FolderWatchToolbarButton` — stays in the top bar, unchanged
- `WatchStrip` — stays below main bar, unchanged
- `SourceEditingStatusBar` — stays below watch strip, unchanged
- `BreadcrumbDocumentContext` — stays in main bar, unchanged
- All action callbacks and state management — no store changes
- All accessibility identifiers and labels — preserved on moved controls

## Edge Cases

- **No file open:** Rail still shows view mode (disabled) and actions menu. Change nav and edit hidden.
- **Narrow window height:** Rail scrolls if it exceeds available height (unlikely with current control count, but defensive).
- **Source editing active:** Edit button hidden in rail. Editing banner appears below top bar as before.

## Testing

- Existing unit tests for `ReaderTopBar` may reference removed controls — update assertions.
- No new unit tests needed for pure layout changes (view-only, no logic).
- Manual verification: all 4 conditional states (no watch, watch active, changes detected, source editing) render correctly.
