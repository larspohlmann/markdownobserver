# Watch Folder: Auto-Open 12 Newest Files

**Issue:** [#64](https://github.com/larspohlmann/markdownobserver/issues/64)
**Date:** 2026-04-02

## Problem

When a watch folder is opened, all files start in the deferred state. No file is automatically loaded and displayed. The user must manually select files to view them.

## Desired Behavior

| Folder size  | Sidebar        | Loaded                              | Selected | Sheet? |
|--------------|----------------|-------------------------------------|----------|--------|
| <= 12 files  | All files      | All loaded                          | Newest   | No     |
| 13-50 files  | All files      | 12 newest loaded, rest deferred     | Newest   | No     |
| > 50 files   | --             | --                                  | --       | Yes (existing behavior) |

- "Newest" means most recently modified by filesystem modification date.
- "Loaded" means fully read from disk and rendered (not deferred).
- "Deferred" means present in sidebar with metadata only, loaded on click.

## Approach: Sort-then-partition in the watch controller

Keep `FolderSnapshotDiffer.markdownFiles` returning alphabetical order (diffing pipeline unaffected). Sort by modification date and partition in `applyInitialAutoOpenMarkdownURLs` instead.

## Design

### 1. Modified threshold in `applyInitialAutoOpenMarkdownURLs`

**File:** `ReaderSidebarFolderWatchOwnership.swift` (`ReaderFolderWatchController`)

Current logic:
- `count > 12` (maximumInitialAutoOpenFileCount) -> file selection sheet, no auto-open
- `count <= 12` -> planner routes all to `openDocumentsBurst`, first file loaded, rest deferred

New logic:
- `count > 50` (performanceWarningFileCount) -> file selection sheet (unchanged)
- `count <= 50` -> sort URLs by modification date (newest first) via `FileManager.attributesOfItem`, partition into:
  - **Load set:** first `min(count, 12)` URLs -> fully loaded
  - **Defer set:** remaining URLs -> deferred sidebar rows

### 2. Two-batch dispatch

After partitioning, dispatch through `openDocumentsBurst` in two calls with different origins:

1. **Load batch** (up to 12 newest): origin `.folderWatchAutoOpen` -- triggers full `openFile` in `openAdditionalDocument`
2. **Defer batch** (remaining): origin `.folderWatchInitialBatchAutoOpen` -- triggers `deferFile` in `openAdditionalDocument`

No new `ReaderOpenOrigin` cases needed. Existing origins already have the correct load/defer routing in `openAdditionalDocument`.

### 3. Newest file selection

After both batches, the controller explicitly selects the document with the newest `fileLastModifiedAt`. This replaces the current behavior of selecting the first file by insertion order (alphabetical).

Applies to all folder sizes (<= 12 and 13-50).

### 4. Changes for <= 12 files

Currently: first file fully loaded, rest deferred (all use `.folderWatchInitialBatchAutoOpen`).

New: all files fully loaded using `.folderWatchAutoOpen` origin. Newest file selected.

### 5. What stays unchanged

- `FolderSnapshotDiffer.markdownFiles` -- still returns alphabetical order (diffing unaffected)
- `> 50 files` -- file selection sheet behavior unchanged
- Live watch events -- `maximumLiveAutoOpenFileCount` and live planner logic untouched
- Deferred file materialization on click -- same as today
- `ReaderFileRouting.plannedOpenFileURLs` dedup logic -- still applies within each batch

## Key files

| File | Change |
|------|--------|
| `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift` | Threshold change, mod-date sort, two-batch dispatch, newest selection |
| `minimark/Models/ReaderFolderWatch.swift` | No new constants needed; existing `maximumInitialAutoOpenFileCount` (12) and `performanceWarningFileCount` (50) reused with new semantics |
| `minimark/Stores/ReaderSidebarDocumentController.swift` | Expose method to select document by newest mod date after burst |
| `minimark/Services/ReaderFolderWatchAutoOpenPlanner.swift` | May need to accept pre-sorted input or skip its own sorting |

## Test strategy

- **Partition logic:** given 20 URLs with known mod dates, verify partition produces correct 12-load + 8-defer sets
- **Small folder:** given 8 URLs, verify all 8 are in load set (none deferred)
- **Large folder gate:** given 55 URLs, verify file selection sheet is triggered
- **Selection:** verify newest file is selected after burst
- **Existing tests:** update `ReaderSidebarDeferredLoadingTests` to reflect that <= 12 files are now fully loaded
