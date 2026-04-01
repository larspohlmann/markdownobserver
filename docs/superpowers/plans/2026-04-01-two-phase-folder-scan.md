# Two-Phase Folder Watch Startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split folder-watch startup into a fast metadata phase and a background content-scan phase, with progress surfaced in the sidebar footer.

**Architecture:** `FolderSnapshotDiffer` gets a metadata-only snapshot builder and a per-file content reader. `FolderChangeWatcher` orchestrates the two-phase startup and exposes an `AsyncStream<ScanProgress>`. The stream flows through `ReaderFolderWatchController` → `ReaderSidebarDocumentController` → `ReaderSidebarWorkspaceView` footer.

**Tech Stack:** Swift, SwiftUI, GCD (`DispatchQueue`), Swift Concurrency (`AsyncStream`)

**Spec:** `docs/superpowers/specs/2026-04-01-two-phase-folder-scan-design.md`

---

### File Map

| File | Change | Responsibility |
|---|---|---|
| `minimark/Services/FolderSnapshotDiffer.swift` | Modify | Add `buildMetadataSnapshot()`, metadata-only `FolderFileSnapshot.init`, `withContent()` |
| `minimark/Services/FolderChangeWatcher.swift` | Modify | Two-phase `completeAsyncStartup()`, `ScanProgress`, `AsyncStream`, `populateContentPhase()` |
| `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift` | Modify | Subscribe to scan progress, publish `contentScanProgress` |
| `minimark/Stores/ReaderSidebarDocumentController.swift` | Modify | Passthrough `contentScanProgress` |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Modify | Conditional footer: progress bar during scan, file count after |
| `minimarkTests/Infrastructure/FolderSnapshotDifferTests.swift` | Create | Unit tests for metadata-only snapshot and content population |
| `minimarkTests/Infrastructure/FolderChangeWatcherScanProgressTests.swift` | Create | Unit tests for `ScanProgress` stream lifecycle |
| `minimarkTests/FolderWatch/FolderWatchControllerScanProgressTests.swift` | Create | Unit tests for controller progress propagation |

---

### Task 1: Metadata-only snapshot in `FolderSnapshotDiffer`

**Files:**
- Modify: `minimark/Services/FolderSnapshotDiffer.swift`
- Create: `minimarkTests/Infrastructure/FolderSnapshotDifferTests.swift`

- [ ] **Step 1: Write the failing test — `buildMetadataSnapshot` returns snapshots with nil markdown**

Create `minimarkTests/Infrastructure/FolderSnapshotDifferTests.swift`:

```swift
//
//  FolderSnapshotDifferTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderSnapshotDifferTests {
    @Test func buildMetadataSnapshotReturnsSnapshotsWithNilMarkdown() throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("note.md")
        try "# Hello".write(to: fileURL, atomically: false, encoding: .utf8)

        let differ = FolderSnapshotDiffer()
        let snapshot = try differ.buildMetadataSnapshot(
            folderURL: directoryURL,
            includeSubfolders: false,
            excludedSubdirectoryURLs: []
        )

        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        #expect(snapshot.count == 1)
        #expect(snapshot[normalizedFileURL] != nil)
        #expect(snapshot[normalizedFileURL]?.markdown == nil)
        #expect(snapshot[normalizedFileURL]?.fileSize > 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderSnapshotDifferTests/buildMetadataSnapshotReturnsSnapshotsWithNilMarkdown 2>&1 | tail -20`

Expected: FAIL — `buildMetadataSnapshot` does not exist.

- [ ] **Step 3: Add metadata-only init to `FolderFileSnapshot` and `buildMetadataSnapshot` to protocol + differ**

In `minimark/Services/FolderSnapshotDiffer.swift`, add a metadata-only initializer to `FolderFileSnapshot`:

```swift
init(metadata: FolderFileMetadata) {
    fileSize = metadata.fileSize
    modificationDate = metadata.modificationDate
    resourceIdentity = metadata.resourceIdentity
    markdown = nil
}
```

Add a `withContent` method to `FolderFileSnapshot` for populating content later:

```swift
func withContent(from url: URL) -> FolderFileSnapshot {
    let content = (try? String(contentsOf: url, encoding: .utf8))
    return FolderFileSnapshot(
        fileSize: fileSize,
        modificationDate: modificationDate,
        resourceIdentity: resourceIdentity,
        markdown: content
    )
}
```

This requires a new memberwise init (the struct currently only has the two convenience inits). Add it as a private init used by `withContent`:

```swift
private init(fileSize: UInt64, modificationDate: Date, resourceIdentity: String, markdown: String?) {
    self.fileSize = fileSize
    self.modificationDate = modificationDate
    self.resourceIdentity = resourceIdentity
    self.markdown = markdown
}
```

Add `buildMetadataSnapshot` to the `FolderSnapshotDiffing` protocol:

```swift
func buildMetadataSnapshot(
    folderURL: URL,
    includeSubfolders: Bool,
    excludedSubdirectoryURLs: [URL]
) throws -> [URL: FolderFileSnapshot]
```

Implement it in `FolderSnapshotDiffer`:

```swift
func buildMetadataSnapshot(
    folderURL: URL,
    includeSubfolders: Bool,
    excludedSubdirectoryURLs: [URL]
) throws -> [URL: FolderFileSnapshot] {
    let markdownURLs = try enumerateMarkdownFiles(
        folderURL: folderURL,
        includeSubfolders: includeSubfolders,
        exclusionMatcher: FolderWatchExclusionMatcher(
            rootFolderURL: folderURL,
            excludedSubdirectoryURLs: excludedSubdirectoryURLs
        )
    )

    var snapshot: [URL: FolderFileSnapshot] = [:]
    for url in markdownURLs {
        snapshot[url] = FolderFileSnapshot(metadata: FolderFileMetadata(url: url))
    }

    return snapshot
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderSnapshotDifferTests/buildMetadataSnapshotReturnsSnapshotsWithNilMarkdown 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Write the failing test — `withContent` populates markdown**

Add to `FolderSnapshotDifferTests`:

```swift
@Test func withContentPopulatesMarkdownFromFileURL() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let fileURL = directoryURL.appendingPathComponent("note.md")
    try "# Hello".write(to: fileURL, atomically: false, encoding: .utf8)

    let metadata = FolderFileMetadata(url: fileURL)
    let metadataOnly = FolderFileSnapshot(metadata: metadata)
    #expect(metadataOnly.markdown == nil)

    let populated = metadataOnly.withContent(from: fileURL)
    #expect(populated.markdown == "# Hello")
    #expect(populated.fileSize == metadataOnly.fileSize)
    #expect(populated.modificationDate == metadataOnly.modificationDate)
}
```

- [ ] **Step 6: Run test to verify it passes** (implementation was already added in step 3)

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderSnapshotDifferTests 2>&1 | tail -20`

Expected: PASS — both tests green.

- [ ] **Step 7: Commit**

```bash
git add minimark/Services/FolderSnapshotDiffer.swift minimarkTests/Infrastructure/FolderSnapshotDifferTests.swift
git commit -m "feat: add metadata-only snapshot and withContent to FolderSnapshotDiffer (#51)"
```

---

### Task 2: `ScanProgress` type and `AsyncStream` on `FolderChangeWatcher`

**Files:**
- Modify: `minimark/Services/FolderChangeWatcher.swift`
- Create: `minimarkTests/Infrastructure/FolderChangeWatcherScanProgressTests.swift`

- [ ] **Step 1: Write the failing test — `ScanProgress` type exists and stream emits progress**

Create `minimarkTests/Infrastructure/FolderChangeWatcherScanProgressTests.swift`:

```swift
//
//  FolderChangeWatcherScanProgressTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderChangeWatcherScanProgressTests {
    private static let defaultPollingInterval: DispatchTimeInterval = .milliseconds(50)
    private static let defaultFallbackPollingInterval: DispatchTimeInterval = .milliseconds(100)
    private static let defaultVerificationDelay: DispatchTimeInterval = .milliseconds(25)

    @Test @MainActor func scanProgressStreamEmitsProgressAndCompletes() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL1 = directoryURL.appendingPathComponent("a.md")
        let fileURL2 = directoryURL.appendingPathComponent("b.md")
        try "# A".write(to: fileURL1, atomically: false, encoding: .utf8)
        try "# B".write(to: fileURL2, atomically: false, encoding: .utf8)

        let watcher = makeFolderChangeWatcher()

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { _ in }
        defer { watcher.stopWatching() }

        var progressUpdates: [FolderChangeWatcher.ScanProgress] = []
        for await progress in watcher.scanProgressStream {
            progressUpdates.append(progress)
        }

        #expect(!progressUpdates.isEmpty)

        let final = try #require(progressUpdates.last)
        #expect(final.total == 2)
        #expect(final.completed == 2)
        #expect(final.isFinished)
    }

    @Test @MainActor func scanProgressStreamEmitsZeroTotalForEmptyFolder() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let watcher = makeFolderChangeWatcher()

        try watcher.startWatching(folderURL: directoryURL, includeSubfolders: false) { _ in }
        defer { watcher.stopWatching() }

        var progressUpdates: [FolderChangeWatcher.ScanProgress] = []
        for await progress in watcher.scanProgressStream {
            progressUpdates.append(progress)
        }

        let final = try #require(progressUpdates.last)
        #expect(final.total == 0)
        #expect(final.completed == 0)
        #expect(final.isFinished)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func makeFolderChangeWatcher() -> FolderChangeWatcher {
        FolderChangeWatcher(
            pollingInterval: Self.defaultPollingInterval,
            fallbackPollingInterval: Self.defaultFallbackPollingInterval,
            verificationDelay: Self.defaultVerificationDelay
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderChangeWatcherScanProgressTests/scanProgressStreamEmitsProgressAndCompletes 2>&1 | tail -20`

Expected: FAIL — `ScanProgress` and `scanProgressStream` don't exist.

- [ ] **Step 3: Add `ScanProgress` type and `AsyncStream` to `FolderChangeWatcher`**

In `minimark/Services/FolderChangeWatcher.swift`:

Add the `ScanProgress` type inside `FolderChangeWatcher`:

```swift
struct ScanProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    var isFinished: Bool { completed == total }
}
```

Add private state for the stream:

```swift
private var scanProgressContinuation: AsyncStream<ScanProgress>.Continuation?
private var _scanProgressStream: AsyncStream<ScanProgress>?
```

Add the public property:

```swift
var scanProgressStream: AsyncStream<ScanProgress> {
    if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
        return _scanProgressStream ?? emptyFinishedStream()
    }
    return queue.sync { _scanProgressStream ?? emptyFinishedStream() }
}

private func emptyFinishedStream() -> AsyncStream<ScanProgress> {
    AsyncStream { continuation in
        continuation.yield(ScanProgress(completed: 0, total: 0))
        continuation.finish()
    }
}
```

In `startWatching`, after resetting state and before `queue.async { completeAsyncStartup }`, create the stream:

```swift
let (stream, continuation) = AsyncStream.makeStream(of: ScanProgress.self)
_scanProgressStream = stream
scanProgressContinuation = continuation
```

In `stopWatching`, finish and clear the stream:

```swift
scanProgressContinuation?.finish()
scanProgressContinuation = nil
_scanProgressStream = nil
```

- [ ] **Step 4: Implement `populateContentPhase()` and wire into `completeAsyncStartup`**

Add `populateContentPhase()` to `FolderChangeWatcher`:

```swift
private func populateContentPhase(startupSequence: UInt64) {
    let urls = Array(lastSnapshot.keys)
    let total = urls.count

    if total == 0 {
        scanProgressContinuation?.yield(ScanProgress(completed: 0, total: 0))
        scanProgressContinuation?.finish()
        scanProgressContinuation = nil
        return
    }

    var completed = 0
    for url in urls {
        guard startupSequence == self.startupSequence else {
            scanProgressContinuation?.finish()
            scanProgressContinuation = nil
            return
        }

        guard let existing = lastSnapshot[url], existing.markdown == nil else {
            completed += 1
            scanProgressContinuation?.yield(ScanProgress(completed: completed, total: total))
            continue
        }

        lastSnapshot[url] = existing.withContent(from: url)
        completed += 1
        scanProgressContinuation?.yield(ScanProgress(completed: completed, total: total))
    }

    scanProgressContinuation?.finish()
    scanProgressContinuation = nil
}
```

Modify `completeAsyncStartup` to use `buildMetadataSnapshot` instead of `buildSnapshot`, then call `populateContentPhase` after directory sources are set up:

Change this block in `completeAsyncStartup`:

```swift
let snapshot: [URL: FolderFileSnapshot]
do {
    snapshot = try snapshotDiffer.buildSnapshot(
        folderURL: folderURL,
        includeSubfolders: includeSubfolders,
        excludedSubdirectoryURLs: excludedSubdirectoryURLs
    )
    clearReportedFailure(for: .startupSnapshot)
} catch {
    snapshot = [:]
    reportFailure(stage: .startupSnapshot, folderURL: folderURL, error: error)
}
```

to:

```swift
let snapshot: [URL: FolderFileSnapshot]
do {
    snapshot = try snapshotDiffer.buildMetadataSnapshot(
        folderURL: folderURL,
        includeSubfolders: includeSubfolders,
        excludedSubdirectoryURLs: excludedSubdirectoryURLs
    )
    clearReportedFailure(for: .startupSnapshot)
} catch {
    snapshot = [:]
    reportFailure(stage: .startupSnapshot, folderURL: folderURL, error: error)
}
```

Then at the end of `completeAsyncStartup`, after `scheduleVerification()`, add:

```swift
populateContentPhase(startupSequence: startupSequence)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderChangeWatcherScanProgressTests 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 6: Run existing watcher tests to verify no regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FileRoutingAndWatcherTests 2>&1 | tail -20`

Expected: PASS — all existing tests still green. The key test `folderChangeWatcherReportsAddedAndModifiedFilesWithPreviousMarkdown` should still pass because `populateContentPhase` runs before `verifyChanges` picks up real changes (the content phase populates `lastSnapshot` entries before the first verification cycle detects modifications).

- [ ] **Step 7: Commit**

```bash
git add minimark/Services/FolderChangeWatcher.swift minimarkTests/Infrastructure/FolderChangeWatcherScanProgressTests.swift
git commit -m "feat: two-phase startup with ScanProgress AsyncStream on FolderChangeWatcher (#51)"
```

---

### Task 3: Progress propagation through `ReaderFolderWatchController`

**Files:**
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`
- Create: `minimarkTests/FolderWatch/FolderWatchControllerScanProgressTests.swift`

- [ ] **Step 1: Add `scanProgressStream` to `FolderChangeWatching` protocol**

In `minimark/Services/FolderChangeWatcher.swift`, add to the `FolderChangeWatching` protocol:

```swift
var scanProgressStream: AsyncStream<FolderChangeWatcher.ScanProgress> { get }
```

Update `TestFolderWatcher` in `minimarkTests/TestSupport/TestDoubles.swift` to conform:

```swift
var scanProgressStreamToReturn: AsyncStream<FolderChangeWatcher.ScanProgress> = AsyncStream { $0.finish() }
var scanProgressStream: AsyncStream<FolderChangeWatcher.ScanProgress> {
    scanProgressStreamToReturn
}
```

- [ ] **Step 2: Write the failing test — controller publishes progress from watcher stream**

Create `minimarkTests/FolderWatch/FolderWatchControllerScanProgressTests.swift`:

```swift
//
//  FolderWatchControllerScanProgressTests.swift
//  minimarkTests
//

import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FolderWatchControllerScanProgressTests {
    @Test @MainActor func controllerPublishesScanProgressFromWatcherStream() async throws {
        let folderWatcher = TestFolderWatcher()
        let (stream, continuation) = AsyncStream.makeStream(of: FolderChangeWatcher.ScanProgress.self)
        folderWatcher.scanProgressStreamToReturn = stream

        let controller = makeController(folderWatcher: folderWatcher)
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder")

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            performInitialAutoOpen: false
        )

        #expect(controller.contentScanProgress == nil)

        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 1, total: 3))

        #expect(await waitUntil { controller.contentScanProgress?.completed == 1 })
        #expect(controller.contentScanProgress?.total == 3)

        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 3, total: 3))
        continuation.finish()

        #expect(await waitUntil { controller.contentScanProgress?.isFinished == true })

        controller.stopWatching()
    }

    @Test @MainActor func controllerClearsScanProgressOnStop() async throws {
        let folderWatcher = TestFolderWatcher()
        let (stream, continuation) = AsyncStream.makeStream(of: FolderChangeWatcher.ScanProgress.self)
        folderWatcher.scanProgressStreamToReturn = stream

        let controller = makeController(folderWatcher: folderWatcher)
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder")

        try controller.startWatching(
            folderURL: folderURL,
            options: ReaderFolderWatchOptions(openMode: .watchChangesOnly, scope: .selectedFolderOnly),
            performInitialAutoOpen: false
        )

        continuation.yield(FolderChangeWatcher.ScanProgress(completed: 1, total: 3))
        #expect(await waitUntil { controller.contentScanProgress != nil })

        controller.stopWatching()
        #expect(controller.contentScanProgress == nil)
    }

    private func makeController(folderWatcher: TestFolderWatcher) -> ReaderFolderWatchController {
        ReaderFolderWatchController(
            folderWatcher: folderWatcher,
            settingsStore: TestSettingsStore(),
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderWatchControllerScanProgressTests/controllerPublishesScanProgressFromWatcherStream 2>&1 | tail -20`

Expected: FAIL — `contentScanProgress` doesn't exist on `ReaderFolderWatchController`.

- [ ] **Step 4: Implement `contentScanProgress` on `ReaderFolderWatchController`**

In `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`:

Add a new published property and subscription task:

```swift
private var scanProgressTask: Task<Void, Never>?

private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress? {
    didSet { onStateChange?() }
}
```

In `startWatching`, after `activeFolderWatchSession = session`, subscribe to the stream:

```swift
scanProgressTask?.cancel()
scanProgressTask = Task { [weak self] in
    for await progress in folderWatcher.scanProgressStream {
        guard !Task.isCancelled else { return }
        self?.contentScanProgress = progress
    }
}
```

In `stopWatching`, add cleanup:

```swift
scanProgressTask?.cancel()
scanProgressTask = nil
contentScanProgress = nil
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderWatchControllerScanProgressTests 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 6: Run all existing folder watch coordination tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderWatchCoordinationTests 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add minimark/Services/FolderChangeWatcher.swift minimark/Stores/ReaderSidebarFolderWatchOwnership.swift minimarkTests/TestSupport/TestDoubles.swift minimarkTests/FolderWatch/FolderWatchControllerScanProgressTests.swift
git commit -m "feat: propagate ScanProgress through ReaderFolderWatchController (#51)"
```

---

### Task 4: Passthrough in `ReaderSidebarDocumentController`

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`

- [ ] **Step 1: Add `contentScanProgress` published property**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, add a new published property:

```swift
@Published private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress?
```

Initialize it to `nil` in `init`.

- [ ] **Step 2: Wire it in `synchronizeFolderWatchState()`**

Add to `synchronizeFolderWatchState()`:

```swift
contentScanProgress = folderWatchController.contentScanProgress
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run full test suite to verify no regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "feat: passthrough contentScanProgress in ReaderSidebarDocumentController (#51)"
```

---

### Task 5: Sidebar footer progress UI

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

- [ ] **Step 1: Add scanning state to footer**

Replace the `sidebarWatchingFooter` method in `ReaderSidebarWorkspaceView`:

```swift
private func sidebarWatchingFooter(session: ReaderFolderWatchSession) -> some View {
    HStack(spacing: 6) {
        if let progress = controller.contentScanProgress, !progress.isFinished {
            ProgressView(value: Double(progress.completed), total: max(Double(progress.total), 1))
                .progressViewStyle(.linear)
                .frame(maxWidth: 60)

            Text("Scanning \(progress.completed)/\(progress.total) files")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            if let progress = controller.contentScanProgress, progress.isFinished, progress.total > 0 {
                Text("\(progress.total) files")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(session.detailSummaryTitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .animation(.easeInOut(duration: 0.3), value: controller.contentScanProgress?.isFinished)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification**

Launch the app, open a folder with several markdown files, and verify:
- Progress bar appears during initial scan with "Scanning X/Y files"
- After scan completes, footer transitions to green dot + file count + folder name
- Stopping the folder watch clears the footer entirely

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "feat: sidebar footer shows scan progress and file count (#51)"
```

---

### Task 6: Delayed transition from scan-complete to steady state

**Files:**
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

- [ ] **Step 1: Add delayed clearing of `contentScanProgress` after completion**

The 0.5s hold is best handled in `ReaderFolderWatchController` so the view doesn't need to manage timers. In the scan progress subscription task, after the `for await` loop finishes (stream completed), add a delay before clearing.

**This replaces the subscription Task from Task 3 step 4.** Modify it to:

```swift
scanProgressTask?.cancel()
scanProgressTask = Task { [weak self] in
    for await progress in folderWatcher.scanProgressStream {
        guard !Task.isCancelled else { return }
        self?.contentScanProgress = progress
    }
    guard !Task.isCancelled else { return }
    try? await Task.sleep(for: .milliseconds(500))
    guard !Task.isCancelled else { return }
    self?.contentScanProgress = nil
}
```

This ensures:
- Progress updates flow through live
- After the stream finishes, the final `isFinished` state holds for 0.5s (bar stays filled)
- Then `contentScanProgress` becomes `nil` (footer transitions to steady state)
- If `stopWatching` fires during the delay, the task is cancelled and progress is cleared immediately

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Adjust the steady state to show file count from session**

Since `contentScanProgress` will be `nil` in steady state (after the delay), the file count needs to persist. Add a `scannedFileCount` property to `ReaderFolderWatchController`:

```swift
private(set) var scannedFileCount: Int? {
    didSet { onStateChange?() }
}
```

Set it from the final progress before clearing:

```swift
scanProgressTask = Task { [weak self] in
    var lastProgress: FolderChangeWatcher.ScanProgress?
    for await progress in folderWatcher.scanProgressStream {
        guard !Task.isCancelled else { return }
        self?.contentScanProgress = progress
        lastProgress = progress
    }
    guard !Task.isCancelled else { return }
    if let lastProgress {
        self?.scannedFileCount = lastProgress.total
    }
    try? await Task.sleep(for: .milliseconds(500))
    guard !Task.isCancelled else { return }
    self?.contentScanProgress = nil
}
```

Clear it in `stopWatching`:

```swift
scannedFileCount = nil
```

Add passthrough in `ReaderSidebarDocumentController`:

```swift
@Published private(set) var scannedFileCount: Int?
```

Wire in `synchronizeFolderWatchState()`:

```swift
scannedFileCount = folderWatchController.scannedFileCount
```

Initialize to `nil` in `init`.

- [ ] **Step 4: Update sidebar footer to use `scannedFileCount` for steady state**

In `ReaderSidebarWorkspaceView`, update the else branch:

```swift
} else {
    Circle()
        .fill(Color.green)
        .frame(width: 6, height: 6)

    if let fileCount = controller.scannedFileCount, fileCount > 0 {
        Text("\(fileCount) files")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    Text(session.detailSummaryTitle)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
}
```

- [ ] **Step 5: Build and run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add minimark/Stores/ReaderSidebarFolderWatchOwnership.swift minimark/Stores/ReaderSidebarDocumentController.swift minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "feat: delayed scan-complete transition with persistent file count (#51)"
```

---

### Task 7: Final integration verification

**Files:** None (verification only)

- [ ] **Step 1: Run full unit test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 2: Manual integration test**

Launch the app and test these scenarios:
1. Open a folder with 5+ markdown files → progress bar appears, fills, transitions to file count
2. Modify a file externally during scan → file opens (with or without diff depending on scan progress)
3. Stop watching during scan → footer disappears, no stale progress
4. Open a favorite → same progress behavior
5. Switch between favorites rapidly → no stale progress from previous watch

- [ ] **Step 3: Final commit if any adjustments needed**

If manual testing revealed issues, fix them and commit.
