# Per-Favorite Workspace State

**Issue:** [#50](https://github.com/larspohlmann/markdownobserver/issues/50)
**Date:** 2026-04-01

## Goal

When reopening a favorited watch folder, restore the full workspace layout — not just the open files. Users shouldn't have to re-pin groups, re-sort, or resize the sidebar every time they switch between favorites.

## Scope

### Persisted per favorite

- File sort mode (`ReaderSidebarSortMode`)
- Group sort mode (`ReaderSidebarSortMode`)
- Sidebar position — left/right (`ReaderMultiFileDisplayMode`)
- Sidebar width (`CGFloat`)
- Pinned group IDs (`Set<String>`)
- Collapsed group IDs (`Set<String>`)

### Deferred

- Window size & position — edge cases with multiple displays, scaling, and macOS window restoration. Follow-up issue.

## Data Model

New struct `ReaderFavoriteWorkspaceState` (Codable, Equatable):

```swift
struct ReaderFavoriteWorkspaceState: Codable, Equatable {
    var fileSortMode: ReaderSidebarSortMode
    var groupSortMode: ReaderSidebarSortMode
    var sidebarPosition: ReaderMultiFileDisplayMode
    var sidebarWidth: CGFloat
    var pinnedGroupIDs: Set<String>
    var collapsedGroupIDs: Set<String>
}
```

All fields are non-optional. A workspace state is always fully specified — no "partially overridden" branches.

`ReaderFavoriteWatchedFolder` gains one new property:

```swift
var workspaceState: ReaderFavoriteWorkspaceState
```

Non-optional. Always present on every favorite.

## State Flow

### On favorite creation

Snapshot current values into a new `ReaderFavoriteWorkspaceState`:
- Sort modes and sidebar position from `ReaderSettings`
- Sidebar width from the current view state
- Pinned/collapsed group IDs from the sidebar view state

### On favorite open

Apply the favorite's `workspaceState` to the active UI:
- Set sort modes, sidebar position, sidebar width
- Restore pinned and collapsed group IDs into the sidebar

### On state change while a favorite is active

Update the active favorite's `workspaceState` in memory immediately. Persist to `ReaderSettings` storage on a natural cadence (e.g., alongside existing favorite save triggers, or debounced).

Global `ReaderSettings` values for sort modes and sidebar position stay untouched — per-favorite state is independent.

### On closing a favorite / opening a non-favorite folder

Revert to global `ReaderSettings` values for sort modes and sidebar position. Pinned/collapsed groups reset to empty. Sidebar width reverts to the default.

### Migration

Existing favorites decoded without a `workspaceState` key get a default constructed from current global settings with empty pinned/collapsed sets and a default sidebar width.

## Implementation Notes

### Sidebar state lifting

`pinnedGroupIDs` and `collapsedGroupIDs` currently live as `@State` in `ReaderSidebarWorkspaceView`. They must be lifted into `ReaderStore` (as published properties) so the store can snapshot and restore them when switching favorites.

### Sidebar width tracking

The current sidebar width needs to be observable so it can be captured into the workspace state. On restore, the stored width is applied back.

### Save triggers

Update the in-memory `workspaceState` on the active favorite immediately on any change (it's just a struct copy). Persist to UserDefaults on a natural cadence — when the favorite is already being saved (e.g., document list changes), or via a debounced write.

### Global settings path unchanged

When no favorite is active, sort modes and sidebar position continue reading from and writing to `ReaderSettings` as they do today. The per-favorite path only activates when a favorite is open.

## Testing

- Snapshot creation captures all current state values correctly
- Restore applies all six values to the active UI
- State changes while a favorite is active update the workspace state (not globals)
- Migration of old favorites without workspace state produces valid defaults
- Closing a favorite reverts to global settings
- Round-trip: create favorite, change state, close, reopen — state is restored
