# Edit Watched Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an "Edit" button to the WatchPill that opens a sheet for toggling subfolder inclusion/exclusion on an active folder watch, with automatic sidebar group updates and favorite sync.

**Architecture:** Reuse the existing `FolderWatchDirectoryScanModel` + `FolderWatchTreeNodeRow` tree UI. Add an `updateExcludedSubdirectories` method to `ReaderFolderWatchController` that restarts the watcher with updated exclusions. Wire the edit flow through `ContentViewCallbacks` to `ReaderWindowRootView`, which presents the sheet, handles the restart, closes excluded documents, and syncs favorites.

**Tech Stack:** SwiftUI, Swift Testing framework, existing `FolderChangeWatching` protocol.

---

### Task 1: Add `updateExcludedSubdirectories` to ReaderFolderWatchController

**Files:**
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift` (after `stopWatching()`)
- Test: `minimarkTests/FolderWatch/FolderWatchControllerUpdateExclusionsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import minimark

@Suite("FolderWatchController Update Exclusions")
@MainActor
struct FolderWatchControllerUpdateExclusionsTests {

    @Test func updateExclusionsRestartsWatcherWithNewPaths() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/test-folder", isDirectory: true)
        let initialOptions = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: ["/tmp/test-folder/excluded"]
        )
        let updatedExclusions = ["/tmp/test-folder/excluded", "/tmp/test-folder/another"]

        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.update-excl.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        try controller.startWatching(folderURL: folderURL, options: initialOptions, performInitialAutoOpen: false)
        let firstSession = controller.activeFolderWatchSession
        #expect(firstSession != nil)
        #expect(firstSession?.options.excludedSubdirectoryPaths == ["/tmp/test-folder/excluded"])
        #expect(watcher.startCallCount == 1)

        try controller.updateExcludedSubdirectories(updatedExclusions)

        let secondSession = controller.activeFolderWatchSession
        #expect(secondSession != nil)
        #expect(secondSession?.options.excludedSubdirectoryPaths == updatedExclusions)
        #expect(secondSession?.folderURL == firstSession?.folderURL)
        #expect(secondSession?.options.openMode == firstSession?.options.openMode)
        #expect(secondSession?.options.scope == firstSession?.options.scope)
        #expect(watcher.startCallCount == 2)
        #expect(watcher.stopCallCount == 1)
    }

    @Test func updateExclusionsThrowsWhenNotWatching() {
        let watcher = TestFolderWatcher()
        let settingsStore = ReaderSettingsStore(
            storage: TestSettingsKeyValueStorage(),
            storageKey: "reader.settings.update-excl-err.\(UUID().uuidString)"
        )
        let controller = ReaderFolderWatchController(
            folderWatcher: watcher,
            settingsStore: settingsStore,
            securityScope: TestSecurityScopeAccess(),
            systemNotifier: TestReaderSystemNotifier(),
            folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
        )

        #expect(throws: FolderWatchUpdateError.self) {
            try controller.updateExcludedSubdirectories(["/some/path"])
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderWatchControllerUpdateExclusionsTests 2>&1 | tail -20`
Expected: FAIL — `updateExcludedSubdirectories` does not exist

- [ ] **Step 3: Write minimal implementation**

Add the error type at the top of `ReaderSidebarFolderWatchOwnership.swift`, after imports:

```swift
enum FolderWatchUpdateError: Error, LocalizedError {
    case noActiveWatch

    var errorDescription: String? {
        switch self {
        case .noActiveWatch:
            return "No folder is currently being watched."
        }
    }
}
```

Add the following method to `ReaderFolderWatchController` in the same file, after `stopWatching()`:

```swift
func updateExcludedSubdirectories(_ paths: [String]) throws {
    guard let session = activeFolderWatchSession else {
        throw FolderWatchUpdateError.noActiveWatch
    }

    let updatedOptions = ReaderFolderWatchOptions(
        openMode: session.options.openMode,
        scope: session.options.scope,
        excludedSubdirectoryPaths: paths
    )

    try startWatching(
        folderURL: session.folderURL,
        options: updatedOptions,
        performInitialAutoOpen: false
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/FolderWatchControllerUpdateExclusionsTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/ReaderSidebarFolderWatchOwnership.swift minimarkTests/FolderWatch/FolderWatchControllerUpdateExclusionsTests.swift
git commit -m "Add updateExcludedSubdirectories to ReaderFolderWatchController"
```

---

### Task 2: Add `updateExcludedSubdirectories` passthrough to ReaderSidebarDocumentController

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift` (after `stopFolderWatch()`)

- [ ] **Step 1: Add passthrough method**

Add after `stopFolderWatch()`:

```swift
func updateFolderWatchExcludedSubdirectories(_ paths: [String]) throws {
    try folderWatchController.updateExcludedSubdirectories(paths)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "Add updateFolderWatchExcludedSubdirectories passthrough"
```

---

### Task 3: Add `updateFavoriteWatchedFolderExclusions` to ReaderSettingsStore+Favorites

**Files:**
- Modify: `minimark/Stores/ReaderSettingsStore+Favorites.swift` (at end of file)

- [ ] **Step 1: Add the method**

Append to `ReaderSettingsStore` extension in `ReaderSettingsStore+Favorites.swift`:

```swift
func updateFavoriteWatchedFolderExclusions(id: UUID, excludedSubdirectoryPaths: [String]) {
    updateSettings { settings in
        guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = settings.favoriteWatchedFolders[index]
        let updatedOptions = ReaderFolderWatchOptions(
            openMode: existing.options.openMode,
            scope: existing.options.scope,
            excludedSubdirectoryPaths: excludedSubdirectoryPaths
        )

        guard existing.options != updatedOptions else {
            return
        }

        settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: updatedOptions,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: existing.openDocumentRelativePaths,
            allKnownRelativePaths: existing.allKnownRelativePaths,
            workspaceState: existing.workspaceState,
            createdAt: existing.createdAt
        )
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Stores/ReaderSettingsStore+Favorites.swift
git commit -m "Add updateFavoriteWatchedFolderExclusions to settings store"
```

---

### Task 4: Create EditFolderWatchSheet

**Files:**
- Create: `minimark/Views/Content/EditFolderWatchSheet.swift`
- Modify: `minimark/Views/Content/FolderWatchOptionsSheet.swift` (make `FolderWatchTreeNodeRow` internal)

This sheet reuses the existing `FolderWatchTreeNodeRow`, `FolderWatchExclusionLogic`, and `FolderWatchDirectoryScanModel` from the codebase. It is a simplified version of `LargeFolderExclusionDialog` without threshold enforcement.

- [ ] **Step 1: Make FolderWatchTreeNodeRow internal**

In `minimark/Views/Content/FolderWatchOptionsSheet.swift`, change `private struct FolderWatchTreeNodeRow` to `struct FolderWatchTreeNodeRow` so the new sheet can use it.

- [ ] **Step 2: Create the sheet view**

Create `minimark/Views/Content/EditFolderWatchSheet.swift`:

```swift
import SwiftUI

struct EditFolderWatchSheet: View {
    let folderURL: URL
    let currentExcludedSubdirectoryPaths: [String]
    let onConfirm: ([String]) -> Void
    let onCancel: () -> Void

    @StateObject private var scanModel = FolderWatchDirectoryScanModel()
    @State private var excludedSubdirectoryPaths: [String]
    @State private var expandedDirectoryPaths: Set<String> = []

    init(
        folderURL: URL,
        currentExcludedSubdirectoryPaths: [String],
        onConfirm: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.folderURL = folderURL
        self.currentExcludedSubdirectoryPaths = currentExcludedSubdirectoryPaths
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._excludedSubdirectoryPaths = State(initialValue: currentExcludedSubdirectoryPaths)
    }

    private var rootNodes: [FolderWatchDirectoryNode] {
        scanModel.rootNode?.children ?? []
    }

    private var activeSubdirectoryCount: Int {
        let totalCount = scanModel.allSubdirectoryPaths.count
        let excludedSet = Set(excludedSubdirectoryPaths)
        let excludedCount = FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: scanModel.allSubdirectoryPaths,
            excludedPaths: excludedSet
        )
        return totalCount - excludedCount
    }

    private var excludedSubdirectoryCount: Int {
        let excludedSet = Set(excludedSubdirectoryPaths)
        return FolderWatchExclusionCalculator.countEffectivelyExcludedPaths(
            in: scanModel.allSubdirectoryPaths,
            excludedPaths: excludedSet
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Subfolders")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .accessibilityAddTraits(.isHeader)

                    Text(folderURL.path)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Button {
                            excludedSubdirectoryPaths = scanModel.allSubdirectoryPaths
                        } label: {
                            Label("Deactivate All", systemImage: "slash.circle")
                        }
                        .disabled(scanModel.allSubdirectoryPaths.isEmpty)

                        Button {
                            excludedSubdirectoryPaths = []
                        } label: {
                            Label("Activate All", systemImage: "checkmark.circle")
                        }
                        .disabled(excludedSubdirectoryPaths.isEmpty)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text("\(activeSubdirectoryCount) active")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)

                    if excludedSubdirectoryCount > 0 {
                        Text("\(excludedSubdirectoryCount) excluded")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if scanModel.isLoading {
                VStack(spacing: 10) {
                    if let progress = scanModel.scanProgress {
                        ProgressView(value: progress.fractionCompleted)
                            .progressViewStyle(.linear)
                            .frame(width: 320)
                            .controlSize(.small)

                        Text("Scanning subdirectories... \(progress.scannedDirectoryCount) folders processed")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning subdirectories...")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            } else if scanModel.summary != nil {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rootNodes) { node in
                            FolderWatchTreeNodeRow(
                                node: node,
                                level: 0,
                                expandedDirectoryPaths: $expandedDirectoryPaths,
                                excludedSubdirectoryPaths: $excludedSubdirectoryPaths
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 280)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            } else {
                Text("Unable to scan this folder tree.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
            }

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(FolderWatchSecondaryActionButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button("Apply") {
                    onConfirm(excludedSubdirectoryPaths)
                }
                .buttonStyle(FolderWatchPrimaryActionButtonStyle(tint: .accentColor))
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(scanModel.isLoading)
            }
        }
        .padding(22)
        .frame(width: 620)
        .onAppear {
            scanModel.scan(folderURL: folderURL)
        }
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/Content/EditFolderWatchSheet.swift minimark/Views/Content/FolderWatchOptionsSheet.swift
git commit -m "Add EditFolderWatchSheet for live subfolder editing"
```

---

### Task 5: Add `onEditSubfolders` callback to WatchPill and wire through the view hierarchy

**Files:**
- Modify: `minimark/Views/Content/WatchPill.swift`
- Modify: `minimark/Views/Content/ContentViewCallbacks.swift`
- Modify: `minimark/ContentView.swift`
- Modify: `minimark/Views/ReaderWindowRootView.swift`

- [ ] **Step 1: Add callback property to WatchPill**

In `WatchPill.swift`, add after line 12 (`onToggleAppearanceLock`):

```swift
let onEditSubfolders: () -> Void
```

- [ ] **Step 2: Add edit button to WatchPill body**

In the `body`, between the path button (ending before `WatchPillFavoriteStarToggle`) and the star toggle, insert:

```swift
if activeFolderWatch.options.scope == .includeSubfolders {
    Button {
        onEditSubfolders()
    } label: {
        Image(systemName: "pencil.circle")
            .font(.system(size: 11, weight: .medium))
            .frame(width: Metrics.controlHeight, height: Metrics.controlHeight)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary.opacity(0.4))
    .help("Edit subfolders")
    .accessibilityLabel("Edit subfolders")
    .accessibilityHint("Choose which subfolders to include or exclude")
}
```

- [ ] **Step 3: Add callback to ContentViewCallbacks**

Add after `onClearRecentManuallyOpenedFiles` in `ContentViewCallbacks`:

```swift
let onEditSubfolders: () -> Void
```

- [ ] **Step 4: Pass callback through ContentView to WatchPill**

In `ContentView.swift`, in the `WatchPill` instantiation, add `onEditSubfolders: callbacks.onEditSubfolders,`.

Also add `onEditSubfolders: {}` to any preview/test WatchPill instantiations.

- [ ] **Step 5: Wire callback in ReaderWindowRootView**

Add state variable near other `@State` vars:

```swift
@State var isEditingSubfolders = false
```

In the `ContentViewCallbacks` construction, add:

```swift
onEditSubfolders: { [self] in
    isEditingSubfolders = true
},
```

Add a `.sheet` modifier near the existing `isFolderWatchOptionsPresented` sheet:

```swift
.sheet(isPresented: $isEditingSubfolders) {
    if let session = sharedFolderWatchSession {
        EditFolderWatchSheet(
            folderURL: session.folderURL,
            currentExcludedSubdirectoryPaths: session.options.excludedSubdirectoryPaths,
            onConfirm: { newExclusions in
                updateFolderWatchExclusions(newExclusions)
                isEditingSubfolders = false
            },
            onCancel: {
                isEditingSubfolders = false
            }
        )
    }
}
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add minimark/Views/Content/WatchPill.swift minimark/Views/Content/ContentViewCallbacks.swift minimark/ContentView.swift minimark/Views/ReaderWindowRootView.swift
git commit -m "Wire onEditSubfolders callback through view hierarchy"
```

---

### Task 6: Add `updateFolderWatchExclusions` orchestration to ReaderWindowRootView

**Files:**
- Modify: `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift`

This is the orchestration method that ties everything together: restart watcher, close excluded documents, sync favorite.

- [ ] **Step 1: Add the orchestration methods**

Add to `ReaderWindowRootView+SidebarCommandFlow.swift`:

```swift
func updateFolderWatchExclusions(_ newExcludedPaths: [String]) {
    guard let session = sharedFolderWatchSession else { return }

    let oldExcludedSet = Set(session.options.excludedSubdirectoryPaths)

    do {
        try sidebarDocumentController.updateFolderWatchExcludedSubdirectories(newExcludedPaths)
    } catch {
        sidebarDocumentController.selectedReaderStore.presentError(error)
        return
    }

    let newExcludedSet = Set(newExcludedPaths)
    let newlyExcludedPaths = newExcludedSet.subtracting(oldExcludedSet)
    if !newlyExcludedPaths.isEmpty {
        closeDocumentsInExcludedPaths(Array(newlyExcludedPaths))
    }

    syncFavoriteExclusionsIfNeeded(newExcludedPaths)

    refreshWindowPresentation()
}

private func closeDocumentsInExcludedPaths(_ excludedPaths: [String]) {
    let excludedPrefixes = excludedPaths.map { path in
        path.hasSuffix("/") ? path : path + "/"
    }

    let documentsToClose = sidebarDocumentController.documents.filter { doc in
        guard let fileURL = doc.readerStore.fileURL else { return false }
        let filePath = fileURL.path
        return excludedPrefixes.contains { filePath.hasPrefix($0) }
    }

    for doc in documentsToClose {
        sidebarDocumentController.closeDocument(doc.id)
    }
}

private func syncFavoriteExclusionsIfNeeded(_ excludedPaths: [String]) {
    guard let favoriteID = activeFavoriteID else { return }
    settingsStore.updateFavoriteWatchedFolderExclusions(
        id: favoriteID,
        excludedSubdirectoryPaths: excludedPaths
    )
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift
git commit -m "Add updateFolderWatchExclusions orchestration with document cleanup and favorite sync"
```

---

### Task 7: Build and test

- [ ] **Step 1: Run full build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run unit tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 3: Fix any build/test failures if needed**
