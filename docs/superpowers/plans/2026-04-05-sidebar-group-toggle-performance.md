# Sidebar Group State Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make sidebar group expand/contract, pin toggle, and sort changes fast with 100+ files by introducing a dedicated `SidebarGroupStateController` that owns all group state and caches computed grouping.

**Architecture:** New `SidebarGroupStateController` (`ObservableObject`) owns group arrangement state (sort mode, pinned IDs, collapsed IDs) and publishes `computedGrouping` and `groupIndicatorStates`. A Combine pipeline recomputes grouping only when arrangement inputs change — not when collapse state changes. The sidebar list is extracted into its own `View` struct so SwiftUI can scope invalidation to just the list. Group state is removed from `ReaderWindowRootView` `@State` and the sort/pin/collapse bindings it currently manages.

**Tech Stack:** Swift, SwiftUI, Combine, Swift Testing

**Spec:** `docs/superpowers/specs/2026-04-05-sidebar-group-toggle-performance-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `minimark/Models/ReaderSidebarGrouping.swift` | Modify | Add `aggregatedIndicatorState(from:)` overload; add `precomputedIndicatorStates` param to `group()` |
| `minimark/Stores/SidebarGroupStateController.swift` | Create | Owns group state (sort, pinned, collapsed), Combine pipeline, `computedGrouping`, `groupIndicatorStates`, favorites persistence helpers |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Modify | Extract `SidebarGroupListContent`; use `SidebarGroupStateController`; remove inline grouping, `isGroupExpanded`, `toggleGroupPin`, `documentRow`, sort menus bindings |
| `minimark/Views/ReaderWindowRootView.swift` | Modify | Remove `sidebarCollapsedGroupIDs`, `sidebarPinnedGroupIDs` `@State`; remove `fileSortModeBinding`, `groupSortModeBinding`; use controller for favorites persistence |
| `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift` | Modify | Replace direct `sidebarPinnedGroupIDs`/`sidebarCollapsedGroupIDs` access with controller methods |
| `minimarkTests/Sidebar/ReaderSidebarGroupingTests.swift` | Modify | Add tests for `aggregatedIndicatorState(from:)` and `precomputedIndicatorStates` |
| `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift` | Create | Tests for recomputation, indicator caching, favorites persistence |

---

### Task 1: Add `aggregatedIndicatorState(from:)` overload and `precomputedIndicatorStates` param

**Files:**
- Modify: `minimark/Models/ReaderSidebarGrouping.swift`
- Test: `minimarkTests/Sidebar/ReaderSidebarGroupingTests.swift`

- [ ] **Step 1: Write failing tests for the new overload**

In `minimarkTests/Sidebar/ReaderSidebarGroupingTests.swift`, add after line 372 (after `aggregatedIndicatorDeletedTakesPriorityOverExternalChange`):

```swift
// MARK: - Indicator Aggregation from Pre-Computed States

@Test func aggregatedIndicatorFromStatesReturnsNoneWhenAllNone() {
    let result = ReaderSidebarGrouping.aggregatedIndicatorState(
        from: [.none, .none, .none]
    )
    #expect(result == .none)
}

@Test func aggregatedIndicatorFromStatesReturnsExternalChangeWhenPresent() {
    let result = ReaderSidebarGrouping.aggregatedIndicatorState(
        from: [.none, .externalChange, .none]
    )
    #expect(result == .externalChange)
}

@Test func aggregatedIndicatorFromStatesReturnsDeletedWhenPresent() {
    let result = ReaderSidebarGrouping.aggregatedIndicatorState(
        from: [.none, .deletedExternalChange]
    )
    #expect(result == .deletedExternalChange)
}

@Test func aggregatedIndicatorFromStatesDeletedTakesPriority() {
    let result = ReaderSidebarGrouping.aggregatedIndicatorState(
        from: [.externalChange, .deletedExternalChange, .none]
    )
    #expect(result == .deletedExternalChange)
}

@Test func aggregatedIndicatorFromStatesHandlesEmptyArray() {
    let result = ReaderSidebarGrouping.aggregatedIndicatorState(from: [])
    #expect(result == .none)
}
```

- [ ] **Step 2: Write failing test for precomputedIndicatorStates**

Add after the above:

```swift
// MARK: - Precomputed Indicator States

@Test @MainActor func groupUsesPrecomputedIndicatorStatesWhenProvided() throws {
    let harness = try ReaderSidebarGroupingTestHarness(
        subdirectories: ["src", "tests"],
        filesPerSubdirectory: 1
    )
    defer { harness.cleanup() }

    let srcPath = harness.directoryPath(for: "src")
    let testsPath = harness.directoryPath(for: "tests")

    let precomputed: [String: ReaderDocumentIndicatorState] = [
        srcPath: .externalChange,
        testsPath: .none
    ]

    let grouping = ReaderSidebarGrouping.group(
        harness.documents,
        precomputedIndicatorStates: precomputed
    )

    guard case .grouped(let groups) = grouping else {
        Issue.record("Expected grouped result")
        return
    }

    let srcGroup = try #require(groups.first { $0.id == srcPath })
    let testsGroup = try #require(groups.first { $0.id == testsPath })
    #expect(srcGroup.indicatorState == .externalChange)
    #expect(testsGroup.indicatorState == .none)
}

@Test @MainActor func groupFallsBackToLiveComputationWhenNoPrecomputedStates() throws {
    let harness = try ReaderSidebarGroupingTestHarness(
        subdirectories: ["src", "tests"],
        filesPerSubdirectory: 1
    )
    defer { harness.cleanup() }

    harness.documentsInSubdirectory("src").first!.readerStore
        .testSetHasUnacknowledgedExternalChange(true)

    let grouping = ReaderSidebarGrouping.group(harness.documents)

    guard case .grouped(let groups) = grouping else {
        Issue.record("Expected grouped result")
        return
    }

    let srcPath = harness.directoryPath(for: "src")
    let srcGroup = try #require(groups.first { $0.id == srcPath })
    #expect(srcGroup.indicatorState == .externalChange)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarGroupingTests 2>&1 | tail -20`
Expected: Compilation errors — `aggregatedIndicatorState(from:)` and `precomputedIndicatorStates` don't exist.

- [ ] **Step 4: Implement the overload**

In `minimark/Models/ReaderSidebarGrouping.swift`, after the closing brace of the existing `aggregatedIndicatorState(for:)` (after line 92), add:

```swift
static func aggregatedIndicatorState(
    from states: [ReaderDocumentIndicatorState]
) -> ReaderDocumentIndicatorState {
    var hasExternalChange = false

    for state in states {
        switch state {
        case .deletedExternalChange:
            return .deletedExternalChange
        case .externalChange:
            hasExternalChange = true
        case .none:
            break
        }
    }

    return hasExternalChange ? .externalChange : .none
}
```

- [ ] **Step 5: Add `precomputedIndicatorStates` parameter to `group()`**

Modify the `group()` signature (line 18) to add the new parameter:

```swift
static func group(
    _ documents: [ReaderSidebarDocumentController.Document],
    sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst,
    directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]? = nil,
    pinnedGroupIDs: Set<String> = [],
    precomputedIndicatorStates: [String: ReaderDocumentIndicatorState]? = nil
) -> ReaderSidebarGrouping {
```

Then modify line 45 inside the `compactMap` closure — replace:

```swift
let indicator = aggregatedIndicatorState(for: docs)
```

With:

```swift
let indicator = precomputedIndicatorStates?[directoryPath]
    ?? aggregatedIndicatorState(for: docs)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarGroupingTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add minimark/Models/ReaderSidebarGrouping.swift minimarkTests/Sidebar/ReaderSidebarGroupingTests.swift
git commit -m "feat: add aggregatedIndicatorState(from:) overload and precomputedIndicatorStates param (#163)"
```

---

### Task 2: Create `SidebarGroupStateController`

**Files:**
- Create: `minimark/Stores/SidebarGroupStateController.swift`
- Create: `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`

This is the core of the feature. The controller owns all group state, uses a Combine pipeline to recompute grouping when arrangement inputs change, and caches indicator states derived from `ReaderSidebarDocumentController.rowStates`.

- [ ] **Step 1: Write failing tests**

Create `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`:

```swift
import Combine
import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct SidebarGroupStateControllerTests {

    @Test @MainActor func recomputesGroupingWhenDocumentsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.count == 2)
    }

    @Test @MainActor func recomputesGroupingWhenSortModeChanges() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["zeta", "alpha"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        controller.sortMode = .nameAscending

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.first?.displayName == "alpha")
    }

    @Test @MainActor func recomputesGroupingWhenPinnedIDsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        // Give all groups the same mod date so only pinning affects order
        for doc in harness.documents {
            doc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let betaPath = harness.directoryPath(for: "beta")
        controller.pinnedGroupIDs = [betaPath]

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.first?.displayName == "beta")
        #expect(groups.first?.isPinned == true)
    }

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
        let groupingAfter = controller.computedGrouping

        // Grouping value should be identical — collapsed is display-only state
        #expect(groupingBefore == groupingAfter)
    }

    @Test @MainActor func groupIndicatorStatesReflectDocumentState() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        harness.documentsInSubdirectory("src").first!.readerStore
            .testSetHasUnacknowledgedExternalChange(true)

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.groupIndicatorStates[srcPath] == .externalChange)
    }

    @Test @MainActor func applyWorkspaceStateRestoresAllGroupState() throws {
        let controller = SidebarGroupStateController()

        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .nameDescending,
            sidebarPosition: .leftSidebar,
            sidebarWidth: 300,
            pinnedGroupIDs: ["/path/a"],
            collapsedGroupIDs: ["/path/b"]
        )

        controller.applyWorkspaceState(state)

        #expect(controller.sortMode == .nameDescending)
        #expect(controller.pinnedGroupIDs == ["/path/a"])
        #expect(controller.collapsedGroupIDs == ["/path/b"])
    }

    @Test @MainActor func workspaceStateSnapshotCapturesCurrentState() throws {
        let controller = SidebarGroupStateController()
        controller.sortMode = .nameAscending
        controller.pinnedGroupIDs = ["/a"]
        controller.collapsedGroupIDs = ["/b"]

        let snapshot = controller.workspaceStateSnapshot()
        #expect(snapshot.sortMode == .nameAscending)
        #expect(snapshot.pinnedGroupIDs == ["/a"])
        #expect(snapshot.collapsedGroupIDs == ["/b"])
    }

    @Test @MainActor func prunesStaleGroupIDsWhenDocumentsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.collapsedGroupIDs = ["/stale/path", harness.directoryPath(for: "src")]
        controller.pinnedGroupIDs = ["/stale/path", harness.directoryPath(for: "src")]

        controller.updateDocuments(harness.documents)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.collapsedGroupIDs == [srcPath])
        #expect(controller.pinnedGroupIDs == [srcPath])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -20`
Expected: Compilation error — `SidebarGroupStateController` does not exist.

- [ ] **Step 3: Create `SidebarGroupStateController`**

Create `minimark/Stores/SidebarGroupStateController.swift`:

```swift
import Combine
import Foundation

@MainActor
final class SidebarGroupStateController: ObservableObject {

    // MARK: - Mutable Inputs

    @Published var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst
    @Published var pinnedGroupIDs: Set<String> = []
    @Published var collapsedGroupIDs: Set<String> = []

    // MARK: - Computed Outputs

    @Published private(set) var computedGrouping: ReaderSidebarGrouping = .flat([])
    @Published private(set) var groupIndicatorStates: [String: ReaderDocumentIndicatorState] = [:]

    // MARK: - Private

    private var documents: [ReaderSidebarDocumentController.Document] = []
    private var recomputeCancellable: AnyCancellable?

    // MARK: - Init

    init() {
        recomputeCancellable = Publishers.CombineLatest(
            $sortMode,
            $pinnedGroupIDs
        )
        .dropFirst()
        .sink { [weak self] _, _ in
            self?.recomputeGrouping()
        }
    }

    // MARK: - Document Updates

    func updateDocuments(_ documents: [ReaderSidebarDocumentController.Document]) {
        self.documents = documents
        pruneStaleGroupIDs()
        rebuildGroupIndicatorStates()
        recomputeGrouping()
    }

    // MARK: - Favorites Persistence

    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) {
        sortMode = state.groupSortMode
        pinnedGroupIDs = state.pinnedGroupIDs
        collapsedGroupIDs = state.collapsedGroupIDs
    }

    struct WorkspaceStateSnapshot {
        let sortMode: ReaderSidebarSortMode
        let pinnedGroupIDs: Set<String>
        let collapsedGroupIDs: Set<String>
    }

    func workspaceStateSnapshot() -> WorkspaceStateSnapshot {
        WorkspaceStateSnapshot(
            sortMode: sortMode,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs
        )
    }

    // MARK: - Group Expansion

    func isGroupExpanded(_ groupID: String) -> Bool {
        !collapsedGroupIDs.contains(groupID)
    }

    func toggleGroupExpansion(_ groupID: String) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
    }

    func toggleGroupPin(_ groupID: String) {
        if pinnedGroupIDs.contains(groupID) {
            pinnedGroupIDs.remove(groupID)
        } else {
            pinnedGroupIDs.insert(groupID)
        }
    }

    // MARK: - Private

    private func recomputeGrouping() {
        let directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]

        if sortMode == .openOrder {
            directoryOrderSourceDocuments = documents
        } else {
            directoryOrderSourceDocuments = documents
        }

        computedGrouping = ReaderSidebarGrouping.group(
            documents,
            sortMode: sortMode,
            directoryOrderSourceDocuments: directoryOrderSourceDocuments,
            pinnedGroupIDs: pinnedGroupIDs,
            precomputedIndicatorStates: groupIndicatorStates
        )
    }

    private func rebuildGroupIndicatorStates() {
        let grouped = Dictionary(grouping: documents) { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false) ?? ""
        }
        var result: [String: ReaderDocumentIndicatorState] = [:]
        for (path, docs) in grouped {
            let states = docs.map { doc in
                ReaderDocumentIndicatorState(
                    hasUnacknowledgedExternalChange: doc.readerStore.hasUnacknowledgedExternalChange,
                    isCurrentFileMissing: doc.readerStore.isCurrentFileMissing
                )
            }
            result[path] = ReaderSidebarGrouping.aggregatedIndicatorState(from: states)
        }
        groupIndicatorStates = result
    }

    private func pruneStaleGroupIDs() {
        let activeGroupIDs = Set(documents.compactMap { document in
            document.readerStore.fileURL?.deletingLastPathComponent()
                .path(percentEncoded: false)
        })
        collapsedGroupIDs.formIntersection(activeGroupIDs)
        pinnedGroupIDs.formIntersection(activeGroupIDs)
    }
}
```

- [ ] **Step 4: Add the file to the Xcode project**

The file needs to be in the minimark target. Add it to the Xcode project:

Run: `ls minimark/Stores/` to confirm file placement, then verify build.

- [ ] **Step 5: Add `Equatable` conformance to `ReaderSidebarGrouping`**

The test `collapsedIDsChangeDoesNotRecomputeGrouping` compares two `ReaderSidebarGrouping` values. In `minimark/Models/ReaderSidebarGrouping.swift`, add `Equatable` conformance.

At the top of the file, change:

```swift
@MainActor
enum ReaderSidebarGrouping {
```

To:

```swift
@MainActor
enum ReaderSidebarGrouping: Equatable {
```

Also add `Equatable` to the `Group` struct:

```swift
struct Group: Identifiable, Equatable {
```

Since all fields (`String`, `URL?`, `[Document]`, `ReaderDocumentIndicatorState`, `Date?`, `Bool`) are already `Equatable`, and `ReaderSidebarDocumentController.Document` is `Identifiable` — we need to check if `Document` is `Equatable`. If not, add conformance based on `id`:

In `minimark/Stores/ReaderSidebarDocumentController.swift`, if `Document` does not already conform to `Equatable`, add:

```swift
struct Document: Identifiable, Equatable {
    let id: UUID
    let readerStore: ReaderStore

    static func == (lhs: Document, rhs: Document) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 7: Run existing sidebar tests to verify no regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarGroupingTests -only-testing:minimarkTests/SidebarRowStateTests -only-testing:minimarkTests/SidebarRowStateDerivationTests 2>&1 | tail -20`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add minimark/Stores/SidebarGroupStateController.swift minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift minimark/Models/ReaderSidebarGrouping.swift minimark/Stores/ReaderSidebarDocumentController.swift
git commit -m "feat: add SidebarGroupStateController for cached group state (#163)"
```

---

### Task 3: Extract `SidebarGroupListContent` view struct

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

This task extracts the `List` content into its own `View` struct that observes `SidebarGroupStateController`. No changes to `ReaderWindowRootView` yet — the workspace view creates the group state controller internally and still receives bindings from the root view (we'll remove those in Task 4).

- [ ] **Step 1: Add `SidebarGroupListContent` struct**

In `minimark/Views/ReaderSidebarWorkspaceView.swift`, before `SidebarGroupDisclosureStyle` (before line 678), add:

```swift
private struct SidebarGroupListContent: View {
    @ObservedObject var groupState: SidebarGroupStateController
    @ObservedObject var controller: ReaderSidebarDocumentController
    let settingsStore: ReaderSettingsStore
    let sortedDocuments: [ReaderSidebarDocumentController.Document]
    @Binding var selectedDocumentIDs: Set<UUID>
    let watchedDocumentIDs: Set<UUID>
    let onUpdateSelection: (Set<UUID>) -> Void
    let onOpenInDefaultApp: (Set<UUID>) -> Void
    let onOpenInApplication: (ReaderExternalApplication, Set<UUID>) -> Void
    let onRevealInFinder: (Set<UUID>) -> Void
    let onStopWatchingFolders: (Set<UUID>) -> Void
    let onCloseDocuments: (Set<UUID>) -> Void
    let onCloseOtherDocuments: (Set<UUID>) -> Void
    let onCloseAllDocuments: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            List(
                selection: Binding(
                    get: { selectedDocumentIDs },
                    set: { onUpdateSelection($0) }
                )
            ) {
                switch groupState.computedGrouping {
                case .flat(let documents):
                    ForEach(documents) { document in
                        documentRow(for: document, allDocuments: sortedDocuments, currentDate: context.date)
                            .tag(document.id)
                    }
                case .grouped(let groups):
                    ForEach(groups) { group in
                        DisclosureGroup(isExpanded: isGroupExpanded(group.id)) {
                            ForEach(group.documents) { document in
                                documentRow(for: document, allDocuments: sortedDocuments, currentDate: context.date)
                                    .tag(document.id)
                            }
                        } label: {
                            ReaderSidebarGroupHeader(
                                displayName: group.displayName,
                                documentCount: group.documents.count,
                                isPinned: group.isPinned,
                                indicatorState: group.indicatorState,
                                settings: settingsStore.currentSettings,
                                onTogglePin: {
                                    groupState.toggleGroupPin(group.id)
                                },
                                onCloseGroup: {
                                    onCloseDocuments(Set(group.documents.map(\.id)))
                                }
                            )
                        }
                        .disclosureGroupStyle(SidebarGroupDisclosureStyle())
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func isGroupExpanded(_ groupID: String) -> Binding<Bool> {
        Binding(
            get: { groupState.isGroupExpanded(groupID) },
            set: { _ in groupState.toggleGroupExpansion(groupID) }
        )
    }

    private func documentRow(
        for document: ReaderSidebarDocumentController.Document,
        allDocuments: [ReaderSidebarDocumentController.Document],
        currentDate: Date
    ) -> some View {
        let rowState = controller.rowStates[document.id]
            ?? controller.deriveRowState(from: document)

        return ReaderSidebarDocumentRow(
            state: rowState,
            currentDate: currentDate,
            settings: settingsStore.currentSettings,
            documents: allDocuments,
            readerStore: document.readerStore,
            watchedDocumentIDs: watchedDocumentIDs,
            selectedDocumentIDs: selectedDocumentIDs,
            canClose: true,
            onOpenInDefaultApp: onOpenInDefaultApp,
            onOpenInApplication: { application, documentIDs in
                onOpenInApplication(application, documentIDs)
            },
            onRevealInFinder: onRevealInFinder,
            onStopWatchingFolders: onStopWatchingFolders,
            onClose: onCloseDocuments,
            onCloseOthers: onCloseOtherDocuments,
            onCloseAll: {
                onCloseAllDocuments()
            }
        )
    }
}
```

- [ ] **Step 2: Add `SidebarGroupStateController` to `ReaderSidebarWorkspaceView` and wire it up**

In `ReaderSidebarWorkspaceView`, add a new property after the existing `@ObservedObject` properties:

```swift
@ObservedObject var groupState: SidebarGroupStateController
```

Remove the following properties from `ReaderSidebarWorkspaceView` (they are now on `groupState`):
- `@Binding var collapsedGroupIDs: Set<String>`
- `@Binding var pinnedGroupIDs: Set<String>`
- `@Binding var fileSortMode: ReaderSidebarSortMode`
- `@Binding var groupSortMode: ReaderSidebarSortMode`

Remove these methods (now on `SidebarGroupListContent` or `groupState`):
- `isGroupExpanded(_:)` (lines 122–133)
- `toggleGroupPin(_:)` (lines 135–141)
- `documentRow(for:allDocuments:currentDate:)` (lines 242–271)

Remove `sidebarGrouping(for:)` (lines 104–120) — now handled by the controller.

Remove the `displayedDocuments` computed property (lines 95–102) — sort logic moves to the caller or stays as a local in `sidebarColumn`.

Remove the `activeDirectoryPaths` computed property and its `.onChange` handler (lines 66–70) — stale ID pruning is now in the controller's `updateDocuments()`.

- [ ] **Step 3: Update `sidebarColumn` to use `SidebarGroupListContent`**

Replace the current `sidebarColumn` body. The `TimelineView` + `List` block (lines 163–203) becomes:

```swift
private var sidebarColumn: some View {
    let sortedDocuments = fileSortMode.sorted(controller.documents) { document in
        ReaderSidebarSortDescriptor(
            displayName: document.readerStore.fileDisplayName,
            lastChangedAt: document.readerStore.fileLastModifiedAt
                ?? document.readerStore.lastExternalChangeAt
                ?? document.readerStore.lastRefreshAt
        )
    }

    return ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
            sidebarToolbar

            Divider()

            SidebarGroupListContent(
                groupState: groupState,
                controller: controller,
                settingsStore: settingsStore,
                sortedDocuments: sortedDocuments,
                selectedDocumentIDs: $selectedDocumentIDs,
                watchedDocumentIDs: watchedDocumentIDs,
                onUpdateSelection: { updateSelection($0) },
                onOpenInDefaultApp: onOpenInDefaultApp,
                onOpenInApplication: { application, documentIDs in
                    onOpenInApplication(application, documentIDs)
                },
                onRevealInFinder: onRevealInFinder,
                onStopWatchingFolders: onStopWatchingFolders,
                onCloseDocuments: onCloseDocuments,
                onCloseOtherDocuments: onCloseOtherDocuments,
                onCloseAllDocuments: onCloseAllDocuments
            )
        }
        .frame(maxHeight: .infinity)

        SidebarScanProgressView(controller: controller)
    }
    .frame(
        minWidth: ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth,
        idealWidth: sidebarWidth,
        maxWidth: isDraggingDivider ? .infinity : max(sidebarWidth, ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth),
        maxHeight: .infinity
    )
    .background(SidebarDividerPositionSetter(
        targetWidth: sidebarWidth,
        placement: sidebarPlacement,
        onDividerDragged: { width in
            onSidebarWidthChanged(width)
        },
        onDividerDragActive: { active in
            isDraggingDivider = active
        }
    ))
    .accessibilityIdentifier("sidebar-column")
}
```

- [ ] **Step 4: Update sort menus to use `groupState`**

In `sidebarGroupSortMenu` (around line 282), replace references to `groupSortMode` with `groupState.sortMode`:

```swift
private var sidebarGroupSortMenu: some View {
    Menu {
        ForEach(ReaderSidebarSortMode.allCases, id: \.self) { mode in
            Button {
                groupState.sortMode = mode
            } label: {
                if mode == groupState.sortMode {
                    Label(mode.displayName, systemImage: "checkmark")
                } else {
                    Text(mode.displayName)
                }
            }
        }
    } label: {
        HStack(spacing: 3) {
            Image(systemName: "folder")
                .font(.system(size: 9, weight: .medium))
            Text(groupState.sortMode.footerLabel)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
```

Similarly update `sidebarFileSortMenu` — this still uses `fileSortMode` which remains a `@Binding` on the workspace view (file sort mode is not group state). **Keep `fileSortMode` as a binding** — it's per-file sort order, not group arrangement.

Actually — re-read the workspace view init. `fileSortMode` is passed from the root view. It stays as-is. Only the group-related bindings are removed.

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: Compilation errors in `ReaderWindowRootView` where it passes the removed bindings. That's expected — Task 4 fixes the root view. For now, temporarily comment out the affected lines in `rootContent` to verify the workspace view compiles.

Actually — this task and Task 4 are tightly coupled. **Instead of commenting out, proceed directly to Task 4 before building.** The build verification happens at the end of Task 4.

- [ ] **Step 6: Commit (combined with Task 4)**

This commit happens at the end of Task 4 since both tasks must land together for compilation.

---

### Task 4: Update `ReaderWindowRootView` to use `SidebarGroupStateController`

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift`
- Modify: `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift`

This task removes group state from the root view and wires up the `SidebarGroupStateController`.

- [ ] **Step 1: Add `SidebarGroupStateController` as `@StateObject`**

In `ReaderWindowRootView`, add after the existing `@StateObject` declarations (around line 31):

```swift
@StateObject var groupStateController = SidebarGroupStateController()
```

- [ ] **Step 2: Remove group state `@State` properties**

Remove these lines from `ReaderWindowRootView`:

```swift
@State var sidebarPinnedGroupIDs: Set<String> = []        // line 25
@State var sidebarCollapsedGroupIDs: Set<String> = []     // line 26
```

- [ ] **Step 3: Remove `fileSortModeBinding` and `groupSortModeBinding`**

Remove `groupSortModeBinding` (lines 114–128) — sort mode is now on the group state controller.

Keep `fileSortModeBinding` (lines 98–112) — file sort is not group state.

- [ ] **Step 4: Update `rootContent` to pass `groupState`**

In `rootContent` (line 416), update the `ReaderSidebarWorkspaceView` init call. Remove the group-related bindings and add `groupState`:

```swift
@ViewBuilder
private var rootContent: some View {
    ReaderSidebarWorkspaceView(
        controller: sidebarDocumentController,
        settingsStore: settingsStore,
        sidebarPlacement: sidebarPlacement,
        groupState: groupStateController,
        fileSortMode: fileSortModeBinding,
        sidebarWidth: sidebarWidth,
        onSidebarWidthChanged: { newWidth in
            sidebarWidth = newWidth
            if activeFavoriteWorkspaceState != nil,
               sidebarDocumentController.documents.count > 1 {
                activeFavoriteWorkspaceState?.sidebarWidth = newWidth
            }
        },
        detail: { store in
            contentView(for: store)
        },
        // ... remaining callbacks unchanged
```

- [ ] **Step 5: Update favorites persistence `onChange` handlers**

Remove the two `onChange` handlers for `sidebarPinnedGroupIDs` and `sidebarCollapsedGroupIDs` (lines 264–273).

Replace with an `onChange` on the group state controller's relevant properties. Add these in the same modifier chain:

```swift
.onChange(of: groupStateController.pinnedGroupIDs) { _, newValue in
    if activeFavoriteWorkspaceState != nil {
        activeFavoriteWorkspaceState?.pinnedGroupIDs = newValue
    }
}
.onChange(of: groupStateController.collapsedGroupIDs) { _, newValue in
    if activeFavoriteWorkspaceState != nil {
        activeFavoriteWorkspaceState?.collapsedGroupIDs = newValue
    }
}
.onChange(of: groupStateController.sortMode) { _, newValue in
    if activeFavoriteWorkspaceState != nil {
        activeFavoriteWorkspaceState?.groupSortMode = newValue
    } else {
        settingsStore.updateSidebarGroupSortMode(newValue)
    }
}
```

- [ ] **Step 6: Update document change observation**

Add an `onChange` to feed documents into the group state controller whenever the document list changes:

```swift
.onChange(of: sidebarDocumentController.documents.map(\.id)) { _, _ in
    groupStateController.updateDocuments(sidebarDocumentController.documents)
}
```

Also call `updateDocuments` on `.onAppear` to initialize:

```swift
.onAppear {
    groupStateController.updateDocuments(sidebarDocumentController.documents)
}
```

- [ ] **Step 7: Update `ReaderWindowRootView+SidebarCommandFlow.swift`**

In `saveSharedFolderWatchAsFavorite` (line 62), replace:

```swift
var workspaceState = ReaderFavoriteWorkspaceState.from(
    settings: settingsStore.currentSettings,
    pinnedGroupIDs: sidebarPinnedGroupIDs,
    collapsedGroupIDs: sidebarCollapsedGroupIDs,
    sidebarWidth: sidebarWidth
)
```

With:

```swift
let groupSnapshot = groupStateController.workspaceStateSnapshot()
var workspaceState = ReaderFavoriteWorkspaceState.from(
    settings: settingsStore.currentSettings,
    pinnedGroupIDs: groupSnapshot.pinnedGroupIDs,
    collapsedGroupIDs: groupSnapshot.collapsedGroupIDs,
    sidebarWidth: sidebarWidth
)
```

In `startFavoriteWatch` (line 108-109), replace:

```swift
sidebarPinnedGroupIDs = entry.workspaceState.pinnedGroupIDs
sidebarCollapsedGroupIDs = entry.workspaceState.collapsedGroupIDs
```

With:

```swift
groupStateController.applyWorkspaceState(entry.workspaceState)
```

In `startWatchingFolder` (lines 230-231), replace:

```swift
sidebarPinnedGroupIDs = []
sidebarCollapsedGroupIDs = []
```

With:

```swift
groupStateController.pinnedGroupIDs = []
groupStateController.collapsedGroupIDs = []
```

- [ ] **Step 8: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 10: Commit (includes Task 3 changes)**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift minimark/Views/ReaderWindowRootView.swift minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift
git commit -m "refactor: integrate SidebarGroupStateController into view hierarchy (#163)"
```

---

### Task 5: Remove redundant chevron animation

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

- [ ] **Step 1: Remove the `.animation` modifier from the chevron**

In `SidebarGroupDisclosureStyle.makeBody`, find the chevron `Image` and remove this line:

```swift
.animation(.easeInOut(duration: 0.15), value: configuration.isExpanded)
```

After removal, the chevron image block should be:

```swift
Image(systemName: "chevron.right")
    .font(.system(size: 9, weight: .bold))
    .foregroundStyle(.secondary)
    .frame(width: 16, height: 16)
    .background(.quaternary.opacity(0.5))
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    .rotationEffect(configuration.isExpanded ? .degrees(90) : .zero)
```

The `withAnimation(.easeInOut(duration: 0.15))` on the button action already covers the animation.

- [ ] **Step 2: Build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "fix: remove redundant chevron animation in sidebar group style (#163)"
```

---

### Task 6: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Build Release configuration**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Release -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED
