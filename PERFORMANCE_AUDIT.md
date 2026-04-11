# Performance Audit: MarkdownObserver

**Date:** April 2026
**Method:** Code-first static analysis (no runtime profiling data)
**Classification categories:** Invalidation fan-out, main-thread I/O, algorithmic complexity, memory pressure, rendering pipeline cost

---

## Summary

The most likely performance bottlenecks in MarkdownObserver are: (1) broad observation invalidation caused by the monolithic `ReaderStore` being read directly from many views, (2) synchronous file I/O and content hashing on the main thread during file change detection and folder scanning, (3) O(n) linear scans with URL normalization in hot paths like sidebar document lookup, and (4) periodic re-renders from `TimelineView` that scale linearly with the number of open documents. The rendering pipeline (markdown → HTML → WKWebView) is reasonably well-optimized with in-place content updates, but the HTML construction embeds the full markdown payload as base64 on every render, creating large transient strings.

All findings below are code-backed hypotheses. Runtime profiling with Instruments (Time Profiler, SwiftUI Instruments template) is recommended to confirm impact before applying fixes.

---

## Findings

### 1. Broad observation fan-out from `ReaderStore`

- **Symptom:** Unnecessary view re-renders when unrelated state changes.
- **Likely cause:** `ReaderStore` is `@Observable` with ~40+ observable properties. Views like `ContentView` and `ReaderWindowRootView` read many of these properties directly. With Swift Observation, any property read during `body` evaluation creates a tracking dependency. A change to `isTOCVisible` or `lastRefreshAt` can re-evaluate views that only care about `fileURL`.
- **Evidence:**
  - `ContentView` reads `readerStore.renderedHTMLDocument`, `readerStore.documentViewMode`, `readerStore.changedRegions`, `readerStore.tocHeadings`, `readerStore.isTOCVisible`, etc. in `body` — a single store mutation invalidates all dependents.
  - `ReaderStore` has ~20 forwarding computed properties (`var fileURL`, `var sourceMarkdown`, etc.) at `ReaderStore.swift:23-44` that delegate to `document`. These are all tracked individually.
  - `ReaderWindowRootView` holds 6+ `@Observable` state objects and creates intermediate arrays like `sidebarDocumentController.documents.map(\.id)` in `onChange` handlers (`ReaderWindowRootView.swift:297`).
- **Fix:** Extract narrow read-surfaces for leaf views. Use `@ObservationIgnored` for properties that don't drive view updates, or create lightweight projection structs (like the existing `ReaderTopBarStoreProjection`) for sub-trees. Consider using `withObservationTracking` in targeted places.
- **Validation:** Use SwiftUI Instruments "View body" counts to measure invalidation breadth before/after.

### 2. Synchronous file I/O on the main thread

- **Symptom:** Brief UI freezes during file change detection, especially with large folders.
- **Likely cause:** Several synchronous file operations happen on `@MainActor`:
  - `FileChangeWatcher.makeContentSignature(for:)` at `FileChangeWatcher.swift:195-206` — memory-maps the entire file content and computes a FNV-1a hash. Called during every file change verification, including the 1-second polling fallback.
  - `ReaderAutoOpenSettler.schedulePollLoop()` at `ReaderAutoOpenSettler.swift:160-202` — reads file content every 100ms on the main thread until the file settles.
  - `urlsSortedByModificationDateDescending()` in `ReaderSidebarFolderWatchOwnership.swift:447-456` — calls `FileManager.default.attributesOfItem(atPath:)` synchronously for every file in the watched folder during initial auto-open.
  - `MarkdownImageResolver.resolve()` at `MarkdownImageResolver.swift:24-67` — runs on `@MainActor` inside `renderCurrentMarkdown()`, reads image files from disk and base64-encodes them.
- **Fix:** Offload file hashing and content reading to background tasks. Cache file signatures more aggressively. Move `MarkdownImageResolver.resolve()` to a background step before the main-thread render.
- **Validation:** Time Profiler — look for `FileManager`/`Data(contentsOf:)` frames on the main thread.

### 3. O(n) linear scans with URL normalization on hot paths

- **Symptom:** Degrading performance as the number of open documents grows.
- **Likely cause:**
  - `document(for:)` in `ReaderSidebarDocumentController.swift:452-461` — linear scan with `ReaderFileRouting.normalizedFileURL()` (which calls `resolvingSymlinksInPath()`) for every file assignment. Called in `executePlan()` for each assignment, making it O(n*m).
  - `watchedDocumentIDs()` in `ReaderSidebarDocumentController.swift:446-449` — linear scan calling `watchApplies(to:)` per document. Used as a computed property re-evaluated during view body rendering.
  - `ReaderFileRouting.normalizedFileURL()` at `ReaderFileRouting.swift:12-14` — calls `standardizedFileURL.resolvingSymlinksInPath()`, which may trigger `stat` syscalls. Called pervasively throughout the codebase.
- **Fix:** Maintain a `Dictionary<URL, ReaderStore>` index in `ReaderSidebarDocumentController`. Pre-normalize URLs on insertion rather than on every lookup. Replace `resolvingSymlinksInPath()` with a simpler normalization for identity comparison where symlinks aren't a concern.
- **Validation:** Instruments system call tracing — count `stat`/`lstat` calls during document-heavy operations.

### 4. `TimelineView` re-renders scale linearly with sidebar rows

- **Symptom:** Increased CPU usage proportional to the number of open documents, even when idle.
- **Likely cause:** Each sidebar row in `ReaderSidebarWorkspaceView` contains a `TimelineView(.periodic(from: .now, by: 5))` (line ~420). With N documents, this produces N re-renders every 5 seconds to update the "last changed" relative timestamp text via `ReaderStatusFormatting.relativeText`.
- **Evidence:** `ReaderSidebarDocumentRow` (in `ReaderSidebarWorkspaceView.swift`) uses `TimelineView` for each row.
- **Fix:** Use a single shared `TimelineView` at the list level and pass the date down, or use a single timer that updates a shared `@Observable` timestamp. Consider only updating timestamps that are within a relevant threshold (e.g., < 1 hour old).
- **Validation:** Time Profiler — compare idle CPU with 5 vs 50 open documents.

### 5. Rendering pipeline creates large transient strings

- **Symptom:** Memory spikes during rapid re-renders (e.g., while editing source).
- **Likely cause:** The rendering pipeline embeds the full markdown content as base64 in the HTML document:
  - `MarkdownRenderingService.render()` at `MarkdownRenderingService.swift:35-62` — calls `payloadEncoder.makePayloadBase64()` which JSON-encodes the full markdown + changed regions, then base64-encodes the result.
  - `ReaderCSSFactory.makeHTMLDocument()` at `ReaderCSSFactory.swift` — embeds `payloadBase64`, `cssBase64`, and optionally `themeJSBase64` inline in the HTML string via string interpolation.
  - For a 100KB markdown file, this creates: original string → JSON Data → base64 String → HTML String. Each step holds a copy until ARC collects.
  - The in-place update path (`applyInPlaceContentUpdateIfPossible` at `MarkdownWebView.swift:253-324`) mitigates this by avoiding full reloads, but still parses the HTML to extract the payload and CSS base64 values via string scanning.
- **Fix:** Consider passing the payload via JavaScript function calls rather than embedding in HTML meta tags. This avoids the need to parse the HTML to extract payloads. For the full-reload path, use `WKWebView.evaluateJavaScript()` to inject the payload after loading a template HTML.
- **Validation:** Allocations instrument — track transient `String` and `Data` objects during source editing.

### 6. Diff computation is O(n*m) in the worst case for large files

- **Symptom:** Lag when switching between significantly different file versions.
- **Likely cause:** `ChangedRegionDiffer.computeChangedRegions()` at `ChangedRegionDiffer.swift:13-50` uses the Differ library's `outputDiffPathTraces` which is O(ND) where N is the line count and D is the edit distance. For very large files with many changes, this can be slow.
  - Additionally, `blocks(for:)` at `ChangedRegionDiffer.swift:52-72` iterates all lines to build block structures, and `block(for:in:)` at line 210-212 does a linear `.first` scan for each changed line — O(blocks * lines).
  - The method is called synchronously on the main thread from `renderCurrentMarkdown()` → `render()` and from `updateSourceDraft()`.
- **Fix:** Build an index (Dictionary) from line number to block in `blocks(for:)` instead of scanning linearly. Consider offloading diff computation to a background task for files above a size threshold.
- **Validation:** Time Profiler — measure `computeChangedRegions` duration for files with 1000+ lines.

### 7. `FolderWatchExclusionMatcher.excludesPath()` is O(F*E)

- **Symptom:** Slow folder scanning with many exclusion paths.
- **Likely cause:** `excludesPath()` at `FolderSnapshotDiffer.swift` does a linear scan through `excludedDirectoryPaths` for every file during enumeration. With F files and E exclusion paths, this is O(F*E).
- **Fix:** Sort exclusion paths and use binary search, or build a prefix trie for O(k) lookup where k is the path depth.
- **Validation:** Instruments — measure folder scan time with 500+ files and 10+ exclusion paths.

### 8. `MarkdownImageResolver` static cache never evicts

- **Symptom:** Gradual memory growth during long sessions with many different images.
- **Likely cause:** `MarkdownImageResolver` at `MarkdownImageResolver.swift:20` uses `private static var cache = [String: String]()` with no eviction policy. Each entry holds the base64-encoded data URI of an image (up to 2MB per the `maxImageSize` limit). Over a long session editing files in different directories, the cache accumulates entries indefinitely.
  - Additionally, the `cacheKey(for:)` method at line 133-136 fetches `FileManager.default.attributesOfItem` on every cache lookup (even for hits), which is synchronous I/O.
- **Fix:** Add an LRU eviction policy or cap the cache size. Cache the modification date alongside the data URI to avoid the redundant `attributesOfItem` call on cache hits.
- **Validation:** Allocations instrument — monitor `MarkdownImageResolver.cache` growth over time.

### 9. `ReaderSidebarGrouping.disambiguatedDisplayNames()` worst-case O(n²)

- **Symptom:** Lag when opening a watched folder with many subdirectories sharing the same leaf name.
- **Likely cause:** `disambiguatedDisplayNames()` at `ReaderSidebarGrouping.swift:247-300` iteratively resolves duplicate directory names by increasing path depth. In the worst case (all directories share the same leaf name), this requires up to `maxDepth` passes over all directories, each pass grouping and filtering — O(n² * d) where d is max path depth.
- **Fix:** Build the disambiguated names in a single pass using a trie-based approach or by pre-computing the minimal distinguishing path depth for each group.
- **Validation:** Benchmark with 50+ directories sharing the same leaf name.

### 10. Multiple rapid observation invalidations in `SidebarGroupStateController`

- **Symptom:** Sidebar flickering or redundant re-renders.
- **Likely cause:** `SidebarGroupStateController.recomputeGrouping()` modifies multiple `@Observable` properties (`computedGrouping`, `isGrouped`, `groupIndicatorStates`) in sequence. Each mutation triggers a separate observation invalidation unless SwiftUI coalesces them within the same run loop tick.
- **Evidence:** `recomputeGrouping()` at `SidebarGroupStateController.swift:171-213` is called from `didSet` on `sortMode`, `fileSortMode`, `pinnedGroupIDs`, and from `updateDocuments`.
- **Fix:** Batch mutations using `withObservationTracking` or restructure to compute all derived state first, then assign atomically. Consider making the grouping a single struct property rather than multiple independent properties.
- **Validation:** SwiftUI Instruments — count invalidations per user interaction.

### 11. `ReaderAutoOpenSettler` polls every 100ms on the main thread

- **Symptom:** CPU usage while waiting for a file to settle during folder watch auto-open.
- **Likely cause:** `schedulePollLoop()` at `ReaderAutoOpenSettler.swift:160-202` creates a `Task` that sleeps for 100ms, then calls `loadFile?(fileURL)` — which reads the file from disk — and compares content. This runs on `@MainActor`. With the default settling interval of 1.0 seconds, this means ~10 file reads on the main thread per settled file.
- **Fix:** Use a DispatchSource file monitor instead of polling, or move the poll loop to a background task and dispatch only the final result to the main actor.
- **Validation:** Time Profiler — measure CPU impact during auto-open of a rapidly-changing file.

### 12. `GroupFrameTracker` runs side effects in view `body`

- **Symptom:** Unpredictable layout behavior.
- **Likely cause:** `GroupFrameTracker` at `ReaderSidebarWorkspaceView.swift:1067-1078` uses a `GeometryReader` that writes to a reference-type cache (`_ = cache.frames[groupID] = proxy.frame(in: .global)`) directly in `body`. Side effects in `body` violate SwiftUI's contract (body can be called multiple times per render).
- **Fix:** Use `.onChange(of:)` or `.background(GeometryReader { ... })` with `onPreferenceChange` to write frame data.
- **Validation:** Code review — this is a correctness issue, not directly measurable with profiling.

---

## Metrics

| Metric | Value | Notes |
| --- | --- | --- |
| CPU (idle, 5 docs) | Unknown | Code-backed hypothesis; needs profiling |
| CPU (idle, 50 docs) | Likely elevated | TimelineView × 50 rows re-rendering every 5s |
| Memory growth | Likely gradual | MarkdownImageResolver static cache, DiffBaselineTracker history |
| Render invalidation breadth | High | ~40 observable properties on ReaderStore, many read per view |
| File I/O on main thread | Present | File hashing, image resolution, settler polling |

Runtime profiling is recommended to populate these metrics.

---

## Priority-Ordered Remediation

| Priority | Finding | Effort | Impact |
| --- | --- | --- | --- |
| 1 | Observation fan-out (#1) | Medium | High — reduces unnecessary re-renders across all views |
| 2 | Main-thread file I/O (#2) | Medium | High — eliminates UI freezes during file operations |
| 3 | Linear scans with URL normalization (#3) | Low | Medium — improves sidebar scalability |
| 4 | TimelineView per-row re-renders (#4) | Low | Medium — reduces idle CPU proportional to document count |
| 5 | Rendering pipeline transient strings (#5) | Medium | Medium — reduces memory pressure during editing |
| 6 | Diff computation on main thread (#6) | Medium | Low-Medium — only affects large-file diff operations |
| 7 | Exclusion path linear scan (#7) | Low | Low — only affects folders with many exclusions |
| 8 | Image resolver cache eviction (#8) | Low | Low — gradual memory growth over long sessions |
| 9 | Grouping O(n²) (#9) | Medium | Low — only with many same-named directories |
| 10 | Grouping state invalidation bursts (#10) | Low | Low-Medium — possible flicker |
| 11 | Settler main-thread polling (#11) | Medium | Low-Medium — only during auto-open |
| 12 | GroupFrameTracker side effects (#12) | Low | Low — correctness fix |

---

## Next Steps

1. **Profile on device** with Instruments (Time Profiler + SwiftUI template) to confirm which findings have measurable impact.
2. Start with **#1 (observation fan-out)** and **#2 (main-thread I/O)** as they have the highest expected impact-to-effort ratio.
3. Use the existing `docs/CPU_DIAGNOSTIC_RUNBOOK.md` and `scripts/run-cpu-diagnostic.sh` to establish baseline metrics before applying changes.
