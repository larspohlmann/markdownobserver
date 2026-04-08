# Edit Watched Folders from WatchPill

## Summary

Add an "Edit" button to the WatchPill that opens a sheet for toggling subfolder inclusion/exclusion on an active folder watch. The sidebar automatically removes groups for excluded folders and adds groups for newly included ones. If the active watch is a favorite, the favorite's exclusion list is updated in place.

## Background

The app already supports subfolder exclusion when *starting* a new folder watch via the `LargeFolderExclusionDialog` inside `FolderWatchOptionsSheet`. However, once a watch is active, there is no way to adjust which subfolders are included. Users must stop watching and start over.

The sidebar groups documents by parent directory. Currently these groups only change when documents are opened or closed — there is no mechanism to add/remove groups based on inclusion changes.

## Design

### 1. WatchPill Edit Button

Add a pencil icon button (`pencil.circle`) between the path button and the star toggle on the WatchPill. Only visible when `scope == .includeSubfolders` (subfolder exclusions are irrelevant for single-folder scope).

New callback on `WatchPill`: `onEditSubfolders: () -> Void`.

### 2. EditFolderWatchSheet (New View)

A new SwiftUI view that reuses the existing tree-toggle UI from `LargeFolderExclusionDialog`:

- Title: "Edit Subfolders" (not "Optimize Large Folder Watch")
- No threshold enforcement — user can freely toggle any subfolder
- Replaces the progress ring / threshold counter with a simpler "N active / M excluded" summary
- Initialized with the current session's `folderURL` and `excludedSubdirectoryPaths`
- Uses `FolderWatchDirectoryScanModel` to scan and display the tree
- On confirm: calls `onConfirm([String])` with the updated exclusion list
- On cancel: dismisses with no changes

### 3. Live Exclusion Update on ReaderFolderWatchController

New method: `updateExcludedSubdirectories(_ paths: [String]) throws`

Implementation:
1. Capture current `folderURL`, `openMode`, `scope` from the active session
2. Call `stopWatching()` (stops watcher, ends security scope)
3. Call `startWatching()` with same folder URL, same open mode/scope, new exclusions, `performInitialAutoOpen: false`
4. The session updates, triggering `folderWatchControllerStateDidChange` → `refreshSharedFolderWatchState()` → sidebar recomputes groups

### 4. Document Cleanup After Exclusion Change

After the watcher restarts, documents whose files fall under newly excluded paths are closed. This causes the sidebar to remove their groups.

New method on `ReaderWindowRootView`: `closeDocumentsInExcludedPaths(_ excludedPaths: [String])` — filters open documents and closes any whose file URL starts with an excluded path prefix.

### 5. Favorite Sync

When the active watch is a favorite (`activeFavoriteID != nil`), after updating exclusions:

- Update the favorite's `options.excludedSubdirectoryPaths` via a new `updateFavoriteWatchedFolderExclusions(id:excludedSubdirectoryPaths:)` method on `ReaderSettingsStore+Favorites`
- This is a small new method since the current API only updates open documents or workspace state, not watch options

### 6. Wiring

- `WatchPill.onEditSubfolders` callback → propagated through `ContentViewCallbacks`
- `ReaderWindowRootView` presents `EditFolderWatchSheet` via `@State var isEditingSubfolders = false`
- On confirm: `updateFolderWatchExclusions` → controller restarts → documents cleaned up → favorite synced → UI refreshes

## Files to Modify

| File | Change |
|------|--------|
| `minimark/Views/Content/WatchPill.swift` | Add edit button, `onEditSubfolders` callback |
| `minimark/Views/Content/EditFolderWatchSheet.swift` | **New file** — edit sheet with tree toggle UI |
| `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift` | Add `updateExcludedSubdirectories(_:)` on `ReaderFolderWatchController` |
| `minimark/Stores/ReaderSidebarDocumentController.swift` | Add passthrough for exclusion update |
| `minimark/Stores/ReaderSettingsStore+Favorites.swift` | Add `updateFavoriteWatchedFolderExclusions` method |
| `minimark/Views/ReaderWindowRootView.swift` | Sheet state, presentation, document cleanup |
| `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift` | `updateFolderWatchExclusions` orchestration method |
| `minimark/Views/Content/ContentViewCallbacks.swift` | Wire `onEditSubfolders` callback |
| `minimark/Views/Content/ContentViewAdapter.swift` | Pass callback through |
| `minimark/ContentView.swift` | Pass callback through to WatchPill |

## Out of Scope

- Changing the root folder path (stop + start a new watch for that)
- Changing scope (selected folder only ↔ include subfolders) mid-watch
- Changing open mode mid-watch
