# @Observable Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate 8 `ObservableObject` classes to `@Observable` so SwiftUI uses property-level tracking instead of whole-object invalidation, fixing the root-level cascade in `ReaderWindowRootView`.

**Architecture:** Each `ObservableObject` class is converted to `@Observable`. View-side `@StateObject` becomes `@State`, `@ObservedObject` becomes plain `var`. Combine `$property` publishers are replaced with `didSet`/callbacks. `ReaderStore` is NOT migrated (tracked in #170).

**Tech Stack:** Swift Observation framework (`@Observable`), SwiftUI, Combine (retained for `settingsPublisher` and `ReaderStore.objectWillChange` subscriptions)

**Spec:** `docs/superpowers/specs/2026-04-05-observable-migration-design.md`

---

### Task 1: Migrate `ReaderFolderWatchAutoOpenWarningCoordinator`

**Files:**
- Modify: `minimark/Support/ReaderFolderWatchAutoOpenWarningCoordinator.swift`

- [ ] **Step 1: Convert class to @Observable**

Replace the class declaration and remove `@Published`:

```swift
// Replace lines 1-6:
import Foundation

@MainActor
@Observable
final class ReaderFolderWatchAutoOpenWarningCoordinator {
    var activeFlow: FolderWatchAutoOpenWarningFlow?
```

Remove `import Combine` (line 1) — it's no longer needed.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: Build succeeds. (This will fail until Task 7 updates the view-side `@StateObject` → `@State`, so this step verifies the class itself compiles.)

- [ ] **Step 3: Commit**

```
git add minimark/Support/ReaderFolderWatchAutoOpenWarningCoordinator.swift
git commit -m "refactor: migrate ReaderFolderWatchAutoOpenWarningCoordinator to @Observable"
```

---

### Task 2: Migrate `FolderWatchAutoOpenSelectionModel` and `FolderWatchAutoOpenWarningFlow`

**Files:**
- Modify: `minimark/Views/FolderWatchAutoOpenFlowView.swift`

- [ ] **Step 1: Convert `FolderWatchAutoOpenSelectionModel` to @Observable**

Replace lines 4-7:

```swift
@MainActor
@Observable
final class FolderWatchAutoOpenSelectionModel {
    let omittedFileURLs: [URL]
    var selectedFileURLs: Set<URL>
```

Remove `@Published` from `selectedFileURLs` (line 7).

- [ ] **Step 2: Convert `FolderWatchAutoOpenWarningFlow` to @Observable and delete forwarding**

Replace lines 35-56:

```swift
@MainActor
@Observable
final class FolderWatchAutoOpenWarningFlow: Identifiable {
    enum Step {
        case warning
        case selection
    }

    let id = UUID()
    let warning: ReaderFolderWatchAutoOpenWarning
    let selectionModel: FolderWatchAutoOpenSelectionModel
    var step: Step

    init(warning: ReaderFolderWatchAutoOpenWarning) {
        self.warning = warning
        self.selectionModel = FolderWatchAutoOpenSelectionModel(omittedFileURLs: warning.omittedFileURLs)
        self.step = .warning
    }
```

Key changes:
- Remove `: ObservableObject` conformance
- Add `@Observable` macro
- Remove `@Published` from `step`
- Delete `selectionChangeObserver` property and the `selectionModel.objectWillChange.sink` in `init`
- With `@Observable`, SwiftUI tracks nested access (`flow.selectionModel.selectedFileURLs`) automatically

- [ ] **Step 3: Update view-side @ObservedObject in same file**

In the same file, two views observe these migrated types:

Line 68: replace `@ObservedObject var flow: FolderWatchAutoOpenWarningFlow` with:
```swift
    var flow: FolderWatchAutoOpenWarningFlow
```

Line 100: replace `@ObservedObject var model: FolderWatchAutoOpenSelectionModel` with:
```swift
    var model: FolderWatchAutoOpenSelectionModel
```

- [ ] **Step 4: Remove unused Combine import if no other Combine usage remains**

Check if `Combine` is still used elsewhere in the file. If not, remove `import Combine` (line 1).

- [ ] **Step 5: Commit**

```
git add minimark/Views/FolderWatchAutoOpenFlowView.swift
git commit -m "refactor: migrate FolderWatchAutoOpenSelectionModel and FolderWatchAutoOpenWarningFlow to @Observable"
```

---

### Task 3: Migrate `WindowAppearanceController`

**Files:**
- Modify: `minimark/Stores/WindowAppearanceController.swift`

- [ ] **Step 1: Convert class to @Observable**

Replace lines 5-8:

```swift
@MainActor
@Observable
final class WindowAppearanceController {
    private(set) var isLocked = false
    private(set) var effectiveAppearance: LockedAppearance
```

Key changes:
- Remove `: ObservableObject`
- Add `@Observable`
- Remove `@Published` from both properties
- Keep `import Combine` — the `settingsPublisher` sink (line 33) still uses Combine
- Keep `AnyCancellable` and the sink in `init` as-is — it subscribes to a `CurrentValueSubject`, not a `@Published` property

- [ ] **Step 2: Commit**

```
git add minimark/Stores/WindowAppearanceController.swift
git commit -m "refactor: migrate WindowAppearanceController to @Observable"
```

---

### Task 4: Migrate `ReaderWindowCoordinator`

**Files:**
- Modify: `minimark/Views/Window/Coordination/ReaderWindowCoordinator.swift`

- [ ] **Step 1: Convert class to @Observable and remove manual objectWillChange**

Replace lines 25-27:

```swift
@MainActor
@Observable
final class ReaderWindowCoordinator {
```

Delete `let objectWillChange = ObservableObjectPublisher()` (was line 27). This publisher was never sent to and served no purpose.

Remove `import Combine` (line 2) if no other Combine usage remains in the file. (Check: the file has no other Combine usage, so remove it.)

- [ ] **Step 2: Commit**

```
git add minimark/Views/Window/Coordination/ReaderWindowCoordinator.swift
git commit -m "refactor: migrate ReaderWindowCoordinator to @Observable"
```

---

### Task 5: Migrate `SidebarGroupStateController`

**Files:**
- Modify: `minimark/Stores/SidebarGroupStateController.swift`
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift` (add callback)

- [ ] **Step 1: Convert class to @Observable with didSet triggers**

Replace lines 1-30:

```swift
import Foundation

@MainActor
@Observable
final class SidebarGroupStateController {

    // MARK: - Mutable Inputs

    var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
        didSet { recomputeGroupingIfNeeded() }
    }
    var fileSortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
        didSet { recomputeGroupingIfNeeded() }
    }
    var pinnedGroupIDs: Set<String> = [] {
        didSet { recomputeGroupingIfNeeded() }
    }
    var collapsedGroupIDs: Set<String> = []

    // MARK: - Computed Outputs

    private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    private(set) var groupIndicatorStates: [String: ReaderDocumentIndicatorState] = [:]

    // MARK: - Private

    private var documents: [ReaderSidebarDocumentController.Document] = []
    private var lastRowStates: [UUID: SidebarRowState] = [:]
    private var suppressRecompute = false
```

Remove `import Combine` (line 1). Remove `recomputeCancellable` and `rowStatesCancellable` properties (old lines 22-23).

- [ ] **Step 2: Add recomputeGroupingIfNeeded guard method**

Add after the private properties:

```swift
    private func recomputeGroupingIfNeeded() {
        guard !suppressRecompute else { return }
        recomputeGrouping()
    }
```

- [ ] **Step 3: Update init — remove subscribeToArrangementChanges()**

Replace the init (old lines 28-30):

```swift
    // MARK: - Init

    init() {}
```

Delete `subscribeToArrangementChanges()` entirely (old lines 111-121).

- [ ] **Step 4: Update applyWorkspaceState to suppress redundant recomputes**

Replace old lines 61-69:

```swift
    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) {
        suppressRecompute = true
        sortMode = state.groupSortMode
        fileSortMode = state.fileSortMode
        pinnedGroupIDs = state.pinnedGroupIDs
        collapsedGroupIDs = state.collapsedGroupIDs
        suppressRecompute = false
        recomputeGrouping()
    }
```

- [ ] **Step 5: Replace $rowStates subscription with callback-based observation**

Replace old `observeRowStates` method (lines 45-50):

```swift
    func observeRowStates(from documentController: ReaderSidebarDocumentController) {
        documentController.onRowStatesChanged = { [weak self] rowStates in
            self?.handleRowStatesChanged(rowStates)
        }
    }
```

- [ ] **Step 6: Add onRowStatesChanged callback to ReaderSidebarDocumentController**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, add after line 32 (`private var storeConfigurator`):

```swift
    var onRowStatesChanged: (([UUID: SidebarRowState]) -> Void)?
```

Then add callback invocations in the two places `rowStates` is mutated:

In `rebuildAllRowStates()` (around line 486), after `rowStates = states`:
```swift
        rowStates = states
        onRowStatesChanged?(states)
```

In `updateRowStateIfNeeded(for:)` (around line 511), after `rowStates[documentID] = newState`:
```swift
            rowStates[documentID] = newState
            onRowStatesChanged?(rowStates)
```

- [ ] **Step 7: Commit**

```
git add minimark/Stores/SidebarGroupStateController.swift minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "refactor: migrate SidebarGroupStateController to @Observable, replace Combine with didSet/callback"
```

---

### Task 6: Migrate `ReaderSidebarDocumentController`

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`

- [ ] **Step 1: Convert class to @Observable**

Replace lines 4-5:

```swift
@MainActor
@Observable
final class ReaderSidebarDocumentController {
```

- [ ] **Step 2: Remove @Published from all 13 properties**

Replace lines 15-27:

```swift
    private(set) var documents: [Document]
    var selectedDocumentID: UUID
    private(set) var selectedWindowTitle: String
    private(set) var selectedFileURL: URL?
    private(set) var selectedHasUnacknowledgedExternalChange: Bool
    private(set) var selectedFolderWatchAutoOpenWarning: ReaderFolderWatchAutoOpenWarning?
    var pendingFileSelectionRequest: ReaderFolderWatchFileSelectionRequest?
    private(set) var activeFolderWatchSession: ReaderFolderWatchSession?
    private(set) var isFolderWatchInitialScanInProgress: Bool
    private(set) var didFolderWatchInitialScanFail: Bool
    private(set) var contentScanProgress: FolderChangeWatcher.ScanProgress?
    private(set) var scannedFileCount: Int?
    private(set) var rowStates: [UUID: SidebarRowState] = [:]
```

Keep `import Combine` — the per-document `ReaderStore.objectWillChange` sinks still use it.

- [ ] **Step 3: Commit**

```
git add minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "refactor: migrate ReaderSidebarDocumentController to @Observable"
```

---

### Task 7: Migrate `ReaderSettingsStore`

**Files:**
- Modify: `minimark/Stores/ReaderSettingsStore.swift`

- [ ] **Step 1: Convert class to @Observable**

Replace line 184:

```swift
@MainActor @Observable final class ReaderSettingsStore: ReaderSettingsStoring {
```

- [ ] **Step 2: Remove objectWillChange publisher and send()**

Delete line 194:
```swift
    let objectWillChange = ObservableObjectPublisher()
```

In `updateSettings` (around line 332), delete:
```swift
        objectWillChange.send()
```

Keep the `CurrentValueSubject` and `settingsPublisher` — they serve Combine subscribers (`WindowAppearanceController`, `ReaderStore`).

Remove `import Combine` only if no other Combine usage remains. (`CurrentValueSubject` and `AnyPublisher` require Combine, so keep it.)

- [ ] **Step 3: Commit**

```
git add minimark/Stores/ReaderSettingsStore.swift
git commit -m "refactor: migrate ReaderSettingsStore to @Observable"
```

---

### Task 8: Update all view-side observation wrappers

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift`
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`
- Modify: `minimark/Views/ReaderSettingsView.swift`
- Modify: `minimark/Commands/ReaderCommands.swift`
- Modify: `minimark/minimarkApp.swift`
- Modify: `minimark/Views/SidebarScanProgressView.swift`

- [ ] **Step 1: Update `ReaderWindowRootView` property declarations**

In `minimark/Views/ReaderWindowRootView.swift`, replace lines 11, 15, 25, 30-32:

```swift
    // Line 11: @ObservedObject var settingsStore → plain var
    var settingsStore: ReaderSettingsStore

    // Line 15: @StateObject var sidebarDocumentController → @State var
    @State var sidebarDocumentController: ReaderSidebarDocumentController

    // Line 25: @StateObject var groupStateController → @State var
    @State var groupStateController = SidebarGroupStateController()

    // Line 30-32: @StateObject → @State
    @State var windowCoordinator: ReaderWindowCoordinator
    @State var appearanceController: WindowAppearanceController
    @State var folderWatchWarningCoordinator = ReaderFolderWatchAutoOpenWarningCoordinator()
```

- [ ] **Step 2: Update `ReaderWindowRootView` init — replace StateObject wrappedValue with direct assignment**

Replace lines 37-56 of init:

```swift
    init(
        seed: ReaderWindowSeed?,
        settingsStore: ReaderSettingsStore,
        multiFileDisplayMode: ReaderMultiFileDisplayMode
    ) {
        self.seed = seed
        self.settingsStore = settingsStore
        self.multiFileDisplayMode = multiFileDisplayMode
        let sidebarDocumentController = ReaderSidebarDocumentController(settingsStore: settingsStore)
        _sidebarDocumentController = State(wrappedValue: sidebarDocumentController)
        _windowCoordinator = State(
            wrappedValue: ReaderWindowCoordinator(
                settingsStore: settingsStore,
                sidebarDocumentController: sidebarDocumentController
            )
        )
        _appearanceController = State(
            wrappedValue: WindowAppearanceController(settingsStore: settingsStore)
        )
    }
```

- [ ] **Step 3: Update `$` bindings to use @Bindable**

In `windowLifecycleBaseView` (lines 120 and 133), the `$folderWatchWarningCoordinator.activeFlow` and `$sidebarDocumentController.pendingFileSelectionRequest` bindings need `@Bindable`. Replace the method body opening:

```swift
    private func windowLifecycleBaseView<Content: View>(_ view: Content) -> some View {
        @Bindable var warningCoordinator = folderWatchWarningCoordinator
        @Bindable var sidebarController = sidebarDocumentController
        return view
            .sheet(item: $warningCoordinator.activeFlow, onDismiss: {
```

And change line 133:
```swift
            .sheet(item: $sidebarController.pendingFileSelectionRequest, onDismiss: {
```

- [ ] **Step 4: Update `ReaderSidebarWorkspaceView`**

In `minimark/Views/ReaderSidebarWorkspaceView.swift`, replace lines 11-13:

```swift
    var controller: ReaderSidebarDocumentController
    var settingsStore: ReaderSettingsStore
    var groupState: SidebarGroupStateController
```

Remove `@ObservedObject` from all three.

- [ ] **Step 5: Update `ReaderSettingsView`**

In `minimark/Views/ReaderSettingsView.swift`, replace line 6:

```swift
    private var settingsStore: ReaderSettingsStore
```

Remove `@ObservedObject`.

- [ ] **Step 6: Update `ReaderCommands`**

In `minimark/Commands/ReaderCommands.swift`, replace line 5:

```swift
    var settingsStore: ReaderSettingsStore
```

Remove `@ObservedObject`.

- [ ] **Step 7: Update `minimarkApp`**

In `minimark/minimarkApp.swift`, replace line 7:

```swift
    @State private var settingsStore: ReaderSettingsStore
```

Replace `@StateObject` with `@State`.

In `init()` (lines 10-11), replace:

```swift
        let settingsStore = ReaderSettingsStore()
        _settingsStore = State(wrappedValue: settingsStore)
```

- [ ] **Step 8: Update `SidebarScanProgressView`**

In `minimark/Views/SidebarScanProgressView.swift`, replace line 4:

```swift
    var controller: ReaderSidebarDocumentController
```

Remove `@ObservedObject`.

- [ ] **Step 9: Build the full project**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -30`

Expected: Build succeeds with no errors. There may be warnings about unused imports — fix any that appear.

- [ ] **Step 10: Commit**

```
git add minimark/Views/ReaderWindowRootView.swift minimark/Views/ReaderSidebarWorkspaceView.swift minimark/Views/ReaderSettingsView.swift minimark/Commands/ReaderCommands.swift minimark/minimarkApp.swift minimark/Views/SidebarScanProgressView.swift
git commit -m "refactor: update all view-side observation wrappers for @Observable migration"
```

---

### Task 9: Update tests

**Files:**
- Modify: `minimarkTests/Core/WindowAppearanceControllerTests.swift`
- Modify: `minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift`
- Modify: `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`

- [ ] **Step 1: Update `WindowAppearanceControllerTests`**

The test `testSingleSettingsChangeProducesOneObjectWillChange` (line 71) subscribes to `objectWillChange`. With `@Observable`, there's no `objectWillChange` publisher. Replace the test to verify the property actually changes:

```swift
    func testSingleSettingsChangeUpdatesEffectiveAppearance() {
        let controller = WindowAppearanceController(settingsStore: settingsStore)

        settingsStore.updateTheme(.newspaper)
        drainMainQueue()

        XCTAssertEqual(controller.effectiveTheme, .newspaper)
    }
```

This is covered by existing `testUnlockedControllerPropagatesThemeChange`, so the test can alternatively be deleted.

Remove `cancellables` property (line 8) and its setUp/tearDown if no other test uses it. Remove `import Combine` (line 2) if unused.

- [ ] **Step 2: Update `ReaderSidebarDocumentControllerTests`**

The test at line 388 subscribes to `objectWillChange.sink`. Replace with direct assertion on the expected state change:

```swift
        unselectedDocument.readerStore.handleObservedFileChange()
        await Task.yield()

        #expect(unselectedDocument.readerStore.lastExternalChangeAt != nil)
        // Verify the row state was updated (the observable effect we care about)
        let rowState = harness.controller.rowStates[unselectedDocument.id]
        #expect(rowState?.indicatorState == .externalChange)
```

Remove the `changeCount` variable and `objectWillChange.sink` subscription.

- [ ] **Step 3: Update `SidebarGroupStateControllerTests`**

The test `collapsedIDsChangeDoesNotRecomputeGrouping` (line 70) subscribes to `$computedGrouping`. With `@Observable`, there's no `$` publisher. Since recomputation is now synchronous via `didSet` and `collapsedGroupIDs` does NOT have a `didSet` trigger (by design — it doesn't affect grouping), verify directly:

```swift
    @Test @MainActor func collapsedIDsChangeDoesNotRecomputeGrouping() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let groupingBefore = controller.computedGrouping
        controller.collapsedGroupIDs.insert("src")

        // computedGrouping should be unchanged — collapsedGroupIDs has no didSet trigger
        #expect(controller.computedGrouping == groupingBefore)
    }
```

`ReaderSidebarGrouping` already conforms to `Equatable`, so the direct comparison works.

Remove `import Combine` (line 1) if no other test in the file uses it. Remove `cancellable` usage.

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -40`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```
git add minimarkTests/Core/WindowAppearanceControllerTests.swift minimarkTests/Sidebar/ReaderSidebarDocumentControllerTests.swift minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift
git commit -m "test: update tests for @Observable migration"
```

---

### Task 10: Final build and full test run

- [ ] **Step 1: Clean build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug clean && xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: Clean build succeeds.

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -40`

Expected: All tests pass.

- [ ] **Step 3: Verify no stale Combine imports**

Run: `rg 'import Combine' minimark/ --files-with-matches` and verify each file still needs it. Files that should still have `import Combine`:
- `ReaderSettingsStore.swift` (CurrentValueSubject)
- `WindowAppearanceController.swift` (settingsPublisher sink)
- `ReaderSidebarDocumentController.swift` (ReaderStore.objectWillChange sinks)
- `ReaderStore.swift` (settingsPublisher sink)
- `ReaderSidebarSelectedStoreProjection.swift` (ReaderStore.$property sinks)

Files that should NOT have `import Combine` after migration:
- `SidebarGroupStateController.swift`
- `ReaderFolderWatchAutoOpenWarningCoordinator.swift`
- `ReaderWindowCoordinator.swift`
- `FolderWatchAutoOpenFlowView.swift` (check if other code in file uses Combine)

- [ ] **Step 4: Commit any cleanup**

```
git add -A
git commit -m "chore: remove stale Combine imports after @Observable migration"
```
