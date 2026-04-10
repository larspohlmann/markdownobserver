# Sidebar Group State Performance

**Issue:** [#163](https://github.com/larspohlmann/markdownobserver/issues/163)
**Date:** 2026-04-05

## Problem

Sidebar group operations (expand/contract, pin/unpin, sort order change) with 100+ files cause noticeable lag. Two compounding causes:

1. **Invalidation scope too wide** — Group state (`collapsedGroupIDs`, `pinnedGroupIDs`) is `@State` on `ReaderWindowRootView`. Any mutation invalidates the root `body`, which recreates `ReaderSidebarWorkspaceView`. Since `sidebarColumn` is a computed property (not its own `View` struct), SwiftUI cannot scope the diff — the entire column re-renders.

2. **O(n) work per render** — `sidebarGrouping()` calls `ReaderSidebarGrouping.group()`, which calls `aggregatedIndicatorState()` for every group. That function reads `readerStore.hasUnacknowledgedExternalChange` and `readerStore.isCurrentFileMissing` for every document on every render.

## Design

### New controller: `SidebarGroupStateController`

A dedicated `@MainActor ObservableObject` that owns all sidebar group state and derived computations. Single responsibility: manage sidebar group state.

```swift
@MainActor
final class SidebarGroupStateController: ObservableObject {
    // --- Mutable inputs ---
    @Published var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst
    @Published var pinnedGroupIDs: Set<String> = []
    @Published var collapsedGroupIDs: Set<String> = []
    @Published var customOrder: [String]?  // future: drag-and-drop reordering

    // --- Computed outputs (read-only) ---
    @Published private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    @Published private(set) var groupIndicatorStates: [String: ReaderDocumentIndicatorState] = [:]

    // --- Document input ---
    func updateDocuments(_ documents: [ReaderSidebarDocumentController.Document]) { ... }

    // --- Favorites persistence ---
    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) { ... }
    func workspaceStateSnapshot() -> (collapsedGroupIDs: Set<String>, pinnedGroupIDs: Set<String>) { ... }
}
```

#### Recomputation strategy

A single Combine pipeline merges the arrangement-relevant publishers and recomputes `computedGrouping` when any of them change:

```swift
Publishers.CombineLatest4($sortMode, $pinnedGroupIDs, $customOrder, documentsSubject)
    .sink { [weak self] sortMode, pinnedIDs, customOrder, documents in
        self?.recomputeGrouping(...)
    }
```

**Triggers recomputation:**
- `documents` changing (document added/removed)
- `sortMode` changing
- `pinnedGroupIDs` changing
- `customOrder` changing (future)

**Does NOT trigger recomputation:**
- `collapsedGroupIDs` changing — pure display state, only causes the list view to re-evaluate (cheaply, since grouping is already cached)

#### Indicator state caching

`groupIndicatorStates` is derived from `ReaderSidebarDocumentController.rowStates` (which already cache per-document indicator state via `SidebarRowState.indicatorState`). No direct `ReaderStore` property reads during grouping.

The controller observes document controller changes (via `objectWillChange`) and rebuilds `groupIndicatorStates` from the cached row states. This feeds into `computedGrouping` via a new `precomputedIndicatorStates` parameter on `ReaderSidebarGrouping.group()`.

### Model changes: `ReaderSidebarGrouping`

Two additions:

1. **`aggregatedIndicatorState(from: [ReaderDocumentIndicatorState])`** — New overload that takes pre-computed indicator states instead of `[Document]`. Pure function, no `ReaderStore` access. Same logic as the existing `aggregatedIndicatorState(for:)`.

2. **`precomputedIndicatorStates` parameter on `group()`** — Optional `[String: ReaderDocumentIndicatorState]?` parameter, defaults to `nil`. When provided, uses cached values instead of calling the per-document version. Existing callers unaffected.

### View changes: extract `SidebarGroupListContent`

Extract the `List` content from `sidebarColumn` (lines 163–203 of `ReaderSidebarWorkspaceView`) into a new `SidebarGroupListContent` struct:

- Observes `SidebarGroupStateController` via `@ObservedObject` — reads `computedGrouping` and `collapsedGroupIDs`
- Observes `ReaderSidebarDocumentController` via `@ObservedObject` — reads `rowStates` for document rows
- Owns `isGroupExpanded(_:)` and `toggleGroupPin(_:)` as thin wrappers that mutate the group state controller
- Contains the `TimelineView` + `List` + `DisclosureGroup` / `ForEach` structure

`sidebarColumn` in `ReaderSidebarWorkspaceView` becomes a thin shell: toolbar + `SidebarGroupListContent` + progress view.

### View changes: `ReaderWindowRootView`

- Remove `@State var sidebarCollapsedGroupIDs` and `@State var sidebarPinnedGroupIDs`
- The `SidebarGroupStateController` is created as `@StateObject` in `ReaderSidebarWorkspaceView` (or `ReaderWindowRootView` if favorites persistence requires it)
- Favorites persistence uses `applyWorkspaceState()` / `workspaceStateSnapshot()` instead of direct `onChange` handlers on individual state properties

### Remove redundant chevron animation

In `SidebarGroupDisclosureStyle`, the `withAnimation(.easeInOut(duration: 0.15))` on the button action already animates the `isExpanded` state change. The separate `.animation(.easeInOut(duration: 0.15), value: configuration.isExpanded)` on the chevron image is redundant and can cause a double animation. Remove it.

## Files changed

| File | Action | Change |
|------|--------|--------|
| `minimark/Stores/SidebarGroupStateController.swift` | Create | New controller: group state, Combine pipeline, computed grouping, indicator caching, favorites persistence |
| `minimark/Models/ReaderSidebarGrouping.swift` | Modify | Add `aggregatedIndicatorState(from:)` overload; add `precomputedIndicatorStates` parameter to `group()` |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Modify | Extract `SidebarGroupListContent`; use `SidebarGroupStateController`; remove inline grouping computation; remove redundant chevron `.animation` |
| `minimark/Views/ReaderWindowRootView.swift` | Modify | Remove `sidebarCollapsedGroupIDs` and `sidebarPinnedGroupIDs` @State; use controller for favorites persistence |
| `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift` | Create | Tests for recomputation triggers, indicator caching, favorites persistence |
| `minimarkTests/Sidebar/ReaderSidebarGroupingTests.swift` | Modify | Add tests for `aggregatedIndicatorState(from:)` overload and `precomputedIndicatorStates` param |

## Testing

- **`SidebarGroupStateControllerTests`** (new):
  - Recomputes grouping when sort mode changes
  - Recomputes grouping when pinned IDs change
  - Does *not* recompute grouping when collapsed IDs change
  - `groupIndicatorStates` updates when document indicator state changes
  - `applyWorkspaceState()` restores all state correctly
  - `workspaceStateSnapshot()` captures current state
  - Stale group ID cleanup when documents change

- **`ReaderSidebarGroupingTests`** (extended):
  - `aggregatedIndicatorState(from:)` overload with various indicator combinations
  - `group()` with `precomputedIndicatorStates` uses cached values
  - `group()` without `precomputedIndicatorStates` falls back to live computation

- **Existing tests** — `ReaderSidebarGroupingTests` and `SidebarRowStateTests` pass unchanged

## Out of scope

- Drag-and-drop group reordering — `customOrder` property is included as an extension point but not implemented
- The 5-second `TimelineView` tick — known baseline cost from PR #157 for relative timestamps
- Migration to `@Observable` — would give per-property granularity but is a separate effort
