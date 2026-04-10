# @Observable Migration for ReaderWindowRootView

**Issue:** larspohlmann/markdownobserver#167
**Date:** 2026-04-05

## Problem

`ReaderWindowRootView` observes 6 `ObservableObject`s via `@StateObject`/`@ObservedObject`. Any `@Published` change on any of them invalidates the root `body`, which rebuilds the entire window tree. High-frequency updates like `contentScanProgress` during folder scans cascade through sidebar and detail views unnecessarily.

## Approach

Migrate all 6 observed objects plus `ReaderSettingsStore` (app-global) and 2 helper flow objects to the Swift Observation framework (`@Observable`). This gives SwiftUI property-level tracking: only views that read the specific changed property re-evaluate.

`ReaderStore` is explicitly out of scope (tracked in #170) due to deep cross-codebase usage.

## Objects to Migrate

| Object | Combine Dependency | Migration Notes |
|---|---|---|
| `ReaderFolderWatchAutoOpenWarningCoordinator` | None | Trivial — remove `ObservableObject`, add `@Observable` |
| `FolderWatchAutoOpenSelectionModel` | None | Trivial |
| `FolderWatchAutoOpenWarningFlow` | Sinks child `objectWillChange` | Delete forwarding — `@Observable` tracks nested access automatically |
| `WindowAppearanceController` | Sink on `settingsPublisher` | Keep Combine sink as-is (subscribes to `CurrentValueSubject`, not `@Published`) |
| `ReaderWindowCoordinator` | Manual `objectWillChange` (never fires) | Remove `objectWillChange` entirely |
| `SidebarGroupStateController` | `CombineLatest3` on own props; sinks `$rowStates` | Replace `CombineLatest3` with `didSet`; replace `$rowStates` with callback |
| `ReaderSidebarDocumentController` | Sinks `ReaderStore.objectWillChange` per document | Keep Combine sinks (`ReaderStore` stays `ObservableObject`) |
| `ReaderSettingsStore` | Manual `objectWillChange` + `CurrentValueSubject` | Remove `ObservableObject`; keep `settingsPublisher` subject for non-view subscribers |

## View-side Changes

### ReaderWindowRootView

```swift
// Before
@ObservedObject var settingsStore: ReaderSettingsStore
@StateObject var sidebarDocumentController: ReaderSidebarDocumentController
@StateObject var groupStateController = SidebarGroupStateController()
@StateObject var windowCoordinator: ReaderWindowCoordinator
@StateObject var appearanceController: WindowAppearanceController
@StateObject var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()

// After
var settingsStore: ReaderSettingsStore
@State var sidebarDocumentController: ReaderSidebarDocumentController
@State var groupStateController = SidebarGroupStateController()
@State var windowCoordinator: ReaderWindowCoordinator
@State var appearanceController: WindowAppearanceController
@State var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()
```

Bindings like `$folderWatchWarningCoordinator.activeFlow` use `@Bindable` inline.

### Other Views

- `ReaderSidebarWorkspaceView`: `@ObservedObject var controller/settingsStore/groupState` become plain `var`
- `ReaderSettingsView`: `@ObservedObject var settingsStore` becomes plain `var`
- `ReaderCommands`: `@ObservedObject var settingsStore` becomes plain `var`
- `minimarkApp`: `@StateObject var settingsStore` becomes `@State var settingsStore`
- `SidebarScanProgressView`: `@ObservedObject var controller` becomes plain `var`
- `ContentView` / `ReaderTopBar`: keep `@ObservedObject var readerStore` (not migrating `ReaderStore`)

## Combine Replacement Patterns

### SidebarGroupStateController — self-subscription

Replace `CombineLatest3` on `$sortMode/$fileSortMode/$pinnedGroupIDs` with `didSet`:

```swift
var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
    didSet { recomputeGroupingIfNeeded() }
}
var fileSortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
    didSet { recomputeGroupingIfNeeded() }
}
var pinnedGroupIDs: Set<String> = [] {
    didSet { recomputeGroupingIfNeeded() }
}

private var suppressRecompute = false

private func recomputeGroupingIfNeeded() {
    guard !suppressRecompute else { return }
    recomputeGrouping()
}
```

`applyWorkspaceState` wraps mutations in `suppressRecompute = true/false` to avoid redundant recomputes.

Delete `subscribeToArrangementChanges()` and `recomputeCancellable`.

### SidebarGroupStateController — $rowStates subscription

Replace `documentController.$rowStates.sink` with a callback:

```swift
// ReaderSidebarDocumentController
var onRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?
// Called wherever rowStates is mutated

// SidebarGroupStateController
func observeRowStates(from documentController: ReaderSidebarDocumentController) {
    documentController.onRowStatesChanged = { [weak self] rowStates in
        self?.handleRowStatesChanged(rowStates)
    }
}
```

Delete `rowStatesCancellable`.

### FolderWatchAutoOpenWarningFlow — objectWillChange forwarding

Delete `selectionChangeObserver` and the `selectionModel.objectWillChange.sink` entirely. With `@Observable`, SwiftUI tracks `flow.selectionModel.selectedFileURLs` access across the nested object boundary automatically.

### ReaderSettingsStore

Remove `let objectWillChange = ObservableObjectPublisher()` and `objectWillChange.send()`. Keep `CurrentValueSubject` and `settingsPublisher` — they serve Combine subscribers (`WindowAppearanceController`, `ReaderStore`).

## Migration Order

1. **Phase 1 — Trivial:** `ReaderFolderWatchAutoOpenWarningCoordinator`, `FolderWatchAutoOpenSelectionModel`
2. **Phase 2 — Drop forwarding:** `FolderWatchAutoOpenWarningFlow`
3. **Phase 3 — Simple:** `WindowAppearanceController`, `ReaderWindowCoordinator`
4. **Phase 4 — Combine to didSet/callback:** `SidebarGroupStateController`, `ReaderSidebarDocumentController`
5. **Phase 5 — App-global:** `ReaderSettingsStore`
6. **Phase 6 — View updates:** `ReaderWindowRootView` + extensions, `ReaderSidebarWorkspaceView`, `ReaderSettingsView`, `ReaderCommands`, `minimarkApp`, `SidebarScanProgressView`
7. **Phase 7 — Tests:** `WindowAppearanceControllerTests`, `ReaderSidebarDocumentControllerTests`, `SidebarGroupStateControllerTests`

## Test Updates

- `WindowAppearanceControllerTests`: replace `objectWillChange.sink` with direct property assertions
- `ReaderSidebarDocumentControllerTests`: replace `objectWillChange.sink` with direct property assertions
- `SidebarGroupStateControllerTests`: replace `$computedGrouping.sink` with synchronous assertion after mutation (recomputation is now synchronous via `didSet`)

## Not Migrating

`ReaderStore` — tracked in #170. It has 5 `@Published` properties, is observed by `ContentView` and `ReaderTopBar`, and `ReaderSidebarDocumentController` subscribes to each store's `objectWillChange`. Migrating it cascades into many more files.
