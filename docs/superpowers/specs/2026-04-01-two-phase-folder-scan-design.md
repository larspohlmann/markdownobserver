# Two-Phase Folder Watch Startup with Progress

**Issue:** [#51](https://github.com/larspohlmann/markdownobserver/issues/51)
**Date:** 2026-04-01

## Problem

When folder watching starts, `FolderChangeWatcher.completeAsyncStartup()` calls `buildSnapshot()` which reads the content of every markdown file synchronously on the watcher queue. Directory sources (change detection) don't activate until this completes. For large folders this delays watcher responsiveness, and there's no visual feedback that scanning is in progress.

## Solution

Split the watcher startup into two phases and surface scan progress in the sidebar footer via an `AsyncStream`.

## Design

### 1. `FolderSnapshotDiffer` Changes

Split `buildSnapshot()` into two operations:

- **`buildMetadataSnapshot() -> [URL: FolderFileSnapshot]`** — enumerate files, read only `FolderFileMetadata` (size, mtime, inode). Returns snapshots with `markdown: nil`. Fast — unblocks directory source activation.
- **`populateContent(snapshot:url:) -> String?`** — read a single file's content. Called per-file during the background scan. The watcher updates its `lastSnapshot` entry after each successful read.

`buildIncrementalSnapshot()` stays unchanged — it already conditionally reads content only for metadata-changed files.

### 2. `FolderChangeWatcher` Two-Phase Startup + `AsyncStream`

`completeAsyncStartup()` changes from:

```
buildSnapshot() → synchronizeDirectorySources() → scheduleVerification()
```

to:

```
buildMetadataSnapshot() → synchronizeDirectorySources() → scheduleVerification() → populateContentPhase()
```

**`populateContentPhase()`** iterates `lastSnapshot` entries, reads content one-by-one via `populateContent(snapshot:url:)`, updates the snapshot entry, and yields progress to the stream after each file.

**`AsyncStream<ScanProgress>`** exposed as a public property on `FolderChangeWatcher`:

```swift
struct ScanProgress {
    let completed: Int
    let total: Int
    var isFinished: Bool { completed == total }
}
```

The stream is created at `startWatching()` and yielded to from the watcher's private dispatch queue during `populateContentPhase()`. A final element with `completed == total` signals completion. The stream finishes (continuation terminates) after that.

**Race with `verifyChanges()`:** During the content phase, a change event may fire. `buildIncrementalSnapshot()` reads content for metadata-changed files. If the content phase hasn't reached that file yet, the incremental snapshot reads its content anyway (as it does today). The content phase then skips files whose `markdown` is already non-nil — no double-read, no conflict.

### 3. Progress Propagation Through the Controller Layer

**`ReaderFolderWatchController`** — subscribes to `folderWatcher.scanProgress` in `startWatching()`. Stores a `Task` that iterates the stream and publishes updates:

```swift
@Published var contentScanProgress: FolderChangeWatcher.ScanProgress?
```

`nil` means no scan active. Non-nil with `isFinished == false` means scanning. Non-nil with `isFinished == true` means just completed (used for the transition animation before clearing).

On `stopWatching()`, the subscription task is cancelled, progress is cleared.

**`ReaderSidebarDocumentController`** — add a passthrough:

```swift
@Published var contentScanProgress: FolderChangeWatcher.ScanProgress?
```

Updated from `folderWatchController.contentScanProgress` via the existing Combine observation pattern used for `isFolderWatchInitialScanInProgress`.

The existing `isFolderWatchInitialScanInProgress` bool can be derived from this new property, keeping backward compatibility.

### 4. Sidebar Footer UI

**During scan** — replace the green dot with a determinate `ProgressView`:

- Horizontal bar (`ProgressView(value: completed, total: total)`) styled narrow/compact
- Label: "Scanning 12/47 files" in the existing 10pt secondary style
- Replaces the green dot + folder name while scanning

**After scan completes** — animate transition to steady state:

- Progress bar fills to 100%
- Brief hold (~0.5s), then crossfade to: green dot + file count label + folder name
- The file count stays visible permanently as a new addition to the footer

**Layout:** Same `sidebarWatchingFooter` in `ReaderSidebarWorkspaceView`. Conditional content based on `controller.contentScanProgress`:

- Active scan: `ProgressView` + "Scanning X/Y files"
- Steady state: green dot + "47 files" + folder name

The transition uses `.animation(.easeInOut)`. After `isFinished` becomes true, a 0.5-second delay fires before `contentScanProgress` is set to `nil`, giving the filled bar time to be visible before the crossfade to steady state.

### 5. Edge Cases

| Scenario | Behavior |
|---|---|
| **Change event during scan** | File opens without diff markers if its content hasn't been scanned yet (`initialDiffBaselineMarkdown: nil`). Subsequent changes after scan completes will have a proper baseline. |
| **Empty folder / no markdown files** | Phase 1 returns empty snapshot. Phase 2 is a no-op. Stream emits single element with `completed: 0, total: 0, isFinished: true`. Footer shows "0 files" + green dot. |
| **Watcher stopped mid-scan** | Subscription task cancelled. Progress cleared. Stream continuation terminates. Partially-read content discarded with the watcher. |
| **Rapid favorite switching** | Stopping a watch cancels any in-flight content phase. New watch creates a fresh stream. No stale progress leaks. |
| **File read failure** | File's `markdown` stays `nil`. Progress still increments (file counted as processed). No diff baseline for that file — same as today's first-open behavior. |

## Affected Files

| File | Change |
|---|---|
| `minimark/Services/FolderSnapshotDiffer.swift` | Split `buildSnapshot()` into `buildMetadataSnapshot()` + `populateContent()` |
| `minimark/Services/FolderChangeWatcher.swift` | Two-phase `completeAsyncStartup()`, `ScanProgress` type, `AsyncStream` property, `populateContentPhase()` |
| `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift` | Subscribe to scan progress stream, publish `contentScanProgress` |
| `minimark/Stores/ReaderSidebarDocumentController.swift` | Passthrough `contentScanProgress` from `ReaderFolderWatchController` |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Conditional footer: progress bar during scan, file count after completion |

## Testing Strategy

- **Unit tests for `FolderSnapshotDiffer`:** `buildMetadataSnapshot()` returns snapshots with `nil` content. `populateContent()` fills in content for a given URL.
- **Unit tests for `FolderChangeWatcher`:** Stream emits correct progress sequence. Content phase skips files already populated by incremental snapshot. Stream terminates on completion.
- **Unit tests for controller layer:** `contentScanProgress` publishes updates from watcher. Cleared on `stopWatching()`.
- **UI: manual verification** of progress bar appearance, fill animation, and transition to file count.
