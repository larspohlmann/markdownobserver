# Watch Folder: Auto-Open 12 Newest Files — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a watch folder is opened, auto-open the 12 most recently modified files (fully loaded), defer the rest in the sidebar, and select the newest file.

**Architecture:** Modify `applyInitialAutoOpenMarkdownURLs` in `ReaderFolderWatchController` to sort scanned URLs by modification date (via `FileManager.attributesOfItem`), partition into load set (top 12) and defer set (rest), dispatch as two batches with different origins. Add `selectDocumentWithNewestModificationDate()` to the document controller for explicit newest-file selection after batches complete.

**Tech Stack:** Swift, SwiftUI, macOS (FileManager, Foundation)

---

### Task 1: Add `selectDocumentWithNewestModificationDate()` to `ReaderSidebarDocumentController`

**Files:**
- Modify: `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`

- [ ] **Step 1: Write the failing test**

In `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`, add:

```swift
@Test @MainActor func selectDocumentWithNewestModificationDateSelectsCorrectDocument() throws {
    let harness = try ReaderSidebarControllerTestHarness()
    defer { harness.cleanup() }

    let olderFileURL = harness.temporaryDirectoryURL.appendingPathComponent("older.md")
    let newerFileURL = harness.temporaryDirectoryURL.appendingPathComponent("newer.md")
    try "# Older".write(to: olderFileURL, atomically: true, encoding: .utf8)
    try "# Newer".write(to: newerFileURL, atomically: true, encoding: .utf8)

    let olderDate = Date(timeIntervalSince1970: 1_000_000)
    let newerDate = Date(timeIntervalSince1970: 2_000_000)
    try FileManager.default.setAttributes([.modificationDate: olderDate], ofItemAtPath: olderFileURL.path)
    try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: newerFileURL.path)

    harness.controller.openDocumentsBurst(
        at: [olderFileURL, newerFileURL],
        origin: .manual
    )

    // After burst, last alphabetical is selected (newer.md < older.md? no, "newer" < "older" alphabetically)
    // Regardless of current selection, calling selectDocumentWithNewestModificationDate should select newer.md
    harness.controller.selectDocumentWithNewestModificationDate()

    let selectedStore = harness.controller.selectedReaderStore
    #expect(selectedStore.fileURL?.lastPathComponent == "newer.md")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests/selectDocumentWithNewestModificationDateSelectsCorrectDocument 2>&1 | tail -5`

Expected: FAIL — `selectDocumentWithNewestModificationDate` does not exist.

- [ ] **Step 3: Write minimal implementation**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, add this method after `focusDocument(at:)` (around line 247):

```swift
func selectDocumentWithNewestModificationDate() {
    let newest = documents
        .filter { $0.readerStore.fileURL != nil }
        .max(by: {
            ($0.readerStore.fileLastModifiedAt ?? .distantPast) < ($1.readerStore.fileLastModifiedAt ?? .distantPast)
        })
    if let newest {
        selectDocument(newest.id)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests/selectDocumentWithNewestModificationDateSelectsCorrectDocument 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift
git commit -m "feat(#64): add selectDocumentWithNewestModificationDate to sidebar controller"
```

---

### Task 2: Add `selectNewestDocumentHandler` callback and wire it up

**Files:**
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`

- [ ] **Step 1: Add the callback property to `ReaderFolderWatchController`**

In `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`, add after the `openEventsHandler` property (line 19):

```swift
var selectNewestDocumentHandler: (() -> Void)?
```

- [ ] **Step 2: Wire the callback in `configureFolderWatchController`**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, inside `configureFolderWatchController()`, add after the `openEventsHandler` block (after line 507):

```swift
folderWatchController.selectNewestDocumentHandler = { [weak self] in
    self?.selectDocumentWithNewestModificationDate()
}
```

- [ ] **Step 3: Run existing tests to verify no regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -5`

Expected: All tests PASS (callback is added but not yet called).

- [ ] **Step 4: Commit**

```bash
git add minimark/Stores/ReaderSidebarFolderWatchOwnership.swift minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "feat(#64): add selectNewestDocumentHandler callback to folder watch controller"
```

---

### Task 3: Rewrite `applyInitialAutoOpenMarkdownURLs` with new behavior

**Files:**
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`

- [ ] **Step 1: Replace `applyInitialAutoOpenMarkdownURLs`**

In `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`, replace the entire `applyInitialAutoOpenMarkdownURLs` method (lines 361-397) with:

```swift
private func applyInitialAutoOpenMarkdownURLs(
    _ markdownURLs: [URL],
    for session: ReaderFolderWatchSession
) {
    guard activeFolderWatchSession == session else {
        return
    }

    if markdownURLs.count > ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount {
        pendingFileSelectionRequest = ReaderFolderWatchFileSelectionRequest(
            folderURL: session.folderURL,
            session: session,
            allFileURLs: markdownURLs
        )
        isInitialMarkdownScanInProgress = false
        return
    }

    pendingFileSelectionRequest = nil

    let currentDocumentFileURL = currentDocumentFileURLProvider?()
    let eligibleURLs = markdownURLs.filter { url in
        let normalized = ReaderFileRouting.normalizedFileURL(url)
        if let currentDocumentFileURL,
           normalized == ReaderFileRouting.normalizedFileURL(currentDocumentFileURL) {
            return false
        }
        return true
    }

    let sortedByModDate = urlsSortedByModificationDateDescending(eligibleURLs)
    let maxLoad = ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount
    let loadURLs = Array(sortedByModDate.prefix(maxLoad))
    let deferURLs = Array(sortedByModDate.dropFirst(maxLoad))

    didInitialMarkdownScanFail = false
    folderWatchAutoOpenWarning = nil

    if !deferURLs.isEmpty {
        let deferEvents = deferURLs.map {
            ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
        }
        dispatchOpenEvents(deferEvents, session: session, origin: .folderWatchInitialBatchAutoOpen)
    }

    if !loadURLs.isEmpty {
        let loadEvents = loadURLs.map {
            ReaderFolderWatchChangeEvent(fileURL: $0, kind: .added)
        }
        dispatchOpenEvents(loadEvents, session: session, origin: .folderWatchAutoOpen)
    }

    selectNewestDocumentHandler?()
    isInitialMarkdownScanInProgress = false
}

private func urlsSortedByModificationDateDescending(_ urls: [URL]) -> [URL] {
    urls.map { url -> (url: URL, modDate: Date) in
        let modDate = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        ))?[.modificationDate] as? Date ?? .distantPast
        return (url, modDate)
    }
    .sorted { $0.modDate > $1.modDate }
    .map(\.url)
}
```

- [ ] **Step 2: Run existing tests to check what breaks**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | grep -E '(FAIL|PASS|error:)' | tail -20`

Expected: `sidebarControllerShowsFileSelectionWhenOverThreshold` will FAIL (it creates 13 files and expects the sheet, but 13 < 50 so no sheet now). Other tests should pass.

- [ ] **Step 3: Commit**

```bash
git add minimark/Stores/ReaderSidebarFolderWatchOwnership.swift
git commit -m "feat(#64): rewrite applyInitialAutoOpenMarkdownURLs with mod-date sort and two-batch dispatch"
```

---

### Task 4: Update existing threshold test

**Files:**
- Modify: `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`

- [ ] **Step 1: Update `sidebarControllerShowsFileSelectionWhenOverThreshold`**

The test currently creates `maximumInitialAutoOpenFileCount + 1` (13) files and expects the sheet. Now the threshold is `performanceWarningFileCount` (50). Replace the test (around line 390):

```swift
@Test @MainActor func sidebarControllerShowsFileSelectionWhenOverThreshold() throws {
    let harness = try ReaderSidebarControllerTestHarness()
    defer { harness.cleanup() }

    let performanceLimit = ReaderFolderWatchAutoOpenPolicy.performanceWarningFileCount
    let fileURLs = (0..<performanceLimit + 1).map { index in
        let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "bulk-%02d.md", index))
        try? "# File \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

    try harness.controller.startWatchingFolder(
        folderURL: harness.temporaryDirectoryURL,
        options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
    )

    #expect(harness.controller.pendingFileSelectionRequest != nil)
    #expect(harness.controller.pendingFileSelectionRequest?.allFileURLs.count == performanceLimit + 1)
    #expect(harness.controller.selectedFolderWatchAutoOpenWarning == nil)
}
```

- [ ] **Step 2: Run the updated test**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests/sidebarControllerShowsFileSelectionWhenOverThreshold 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift
git commit -m "test(#64): update file selection sheet threshold test from 12 to 50"
```

---

### Task 5: Add test for 13-50 file range (12 loaded + rest deferred)

**Files:**
- Modify: `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`

- [ ] **Step 1: Write the test**

Add to `ReaderSidebarDocumentControllerTests`:

```swift
@Test @MainActor func sidebarControllerAutoOpens12NewestAndDefersRestForMediumFolder() throws {
    let harness = try ReaderSidebarControllerTestHarness()
    defer { harness.cleanup() }

    let fileCount = 20
    var fileURLs: [URL] = []
    for index in 0..<fileCount {
        let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "note-%02d.md", index))
        try "# Note \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
        let modDate = Date(timeIntervalSince1970: Double(1_000_000 + index * 1000))
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
        fileURLs.append(fileURL)
    }
    harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

    try harness.controller.startWatchingFolder(
        folderURL: harness.temporaryDirectoryURL,
        options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
    )

    #expect(harness.controller.pendingFileSelectionRequest == nil)
    // 20 files + 1 initial empty doc slot = 20 total (empty slot reused by first file)
    #expect(harness.controller.documents.count == fileCount)

    let loadedDocs = harness.controller.documents.filter { !$0.readerStore.isDeferredDocument }
    let deferredDocs = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }

    #expect(loadedDocs.count == ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)
    #expect(deferredDocs.count == fileCount - ReaderFolderWatchAutoOpenPolicy.maximumInitialAutoOpenFileCount)

    // The 12 loaded docs should be the 12 newest by modification date (note-08 through note-19)
    let loadedFileNames = Set(loadedDocs.compactMap { $0.readerStore.fileURL?.lastPathComponent })
    for index in (fileCount - 12)..<fileCount {
        #expect(loadedFileNames.contains(String(format: "note-%02d.md", index)))
    }

    // Newest file (note-19) should be selected
    #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "note-19.md")
}
```

- [ ] **Step 2: Run the test**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests/sidebarControllerAutoOpens12NewestAndDefersRestForMediumFolder 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift
git commit -m "test(#64): add test for 13-50 file range with 12 loaded and rest deferred"
```

---

### Task 6: Add test for small folder (all loaded, newest selected)

**Files:**
- Modify: `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`

- [ ] **Step 1: Write the test**

Add to `ReaderSidebarDocumentControllerTests`:

```swift
@Test @MainActor func sidebarControllerLoadsAllFilesAndSelectsNewestForSmallFolder() throws {
    let harness = try ReaderSidebarControllerTestHarness()
    defer { harness.cleanup() }

    let fileCount = 5
    var fileURLs: [URL] = []
    for index in 0..<fileCount {
        let fileURL = harness.temporaryDirectoryURL.appendingPathComponent(String(format: "doc-%02d.md", index))
        try "# Doc \(index)".write(to: fileURL, atomically: true, encoding: .utf8)
        let modDate = Date(timeIntervalSince1970: Double(1_000_000 + index * 1000))
        try FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: fileURL.path)
        fileURLs.append(fileURL)
    }
    harness.folderWatchControllerWatcher.markdownFilesToReturn = fileURLs

    try harness.controller.startWatchingFolder(
        folderURL: harness.temporaryDirectoryURL,
        options: ReaderFolderWatchOptions(openMode: .openAllMarkdownFiles, scope: .selectedFolderOnly)
    )

    #expect(harness.controller.pendingFileSelectionRequest == nil)
    #expect(harness.controller.documents.count == fileCount)

    // All files should be fully loaded (none deferred)
    let deferredDocs = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }
    #expect(deferredDocs.isEmpty)

    for document in harness.controller.documents {
        #expect(!document.readerStore.sourceMarkdown.isEmpty)
    }

    // Newest file (doc-04) should be selected
    #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "doc-04.md")
}
```

- [ ] **Step 2: Run the test**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests/sidebarControllerLoadsAllFilesAndSelectsNewestForSmallFolder 2>&1 | tail -5`

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift
git commit -m "test(#64): add test for small folder — all loaded, newest selected"
```

---

### Task 7: Run full test suite and fix any remaining failures

**Files:**
- Possibly modify: any test file with regressions

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | grep -E '(Test Suite|Executed|FAIL)' | tail -20`

Expected: All tests PASS. If any fail, investigate and fix.

- [ ] **Step 2: Commit any fixes**

```bash
git add -A && git commit -m "test(#64): fix remaining test regressions from auto-open change"
```

(Skip this step if no fixes were needed.)
