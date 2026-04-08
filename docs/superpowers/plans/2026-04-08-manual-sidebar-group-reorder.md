# Manual Sidebar Group Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to drag-and-drop sidebar group headers to reorder groups manually, with the order persisting in favorites and as session state.

**Architecture:** Add a `.manualOrder` case to `ReaderSidebarSortMode` (hidden from sort menu), store `manualGroupOrder: [String]?` in `SidebarGroupStateController`, apply it as a post-processing step after the existing algorithmic grouping, and implement custom drag-and-drop on group section headers within the existing `ScrollView + LazyVStack`.

**Tech Stack:** SwiftUI, Swift Observation framework, `NSItemProvider` for drag-and-drop.

---

### Task 1: Add `.manualOrder` case to `ReaderSidebarSortMode`

**Files:**
- Modify: `minimark/Models/ReaderSidebarSortMode.swift`
- Test: `minimarkTests/Core/ReaderSettingsAndModelsTests.swift` (verify existing tests still pass)

- [ ] **Step 1: Add the new case and custom CaseIterable**

In `minimark/Models/ReaderSidebarSortMode.swift`, change the enum to add `.manualOrder` and provide an explicit `allCases` that excludes it:

```swift
nonisolated enum ReaderSidebarSortMode: String, CaseIterable, Codable, Sendable {
    case openOrder
    case nameAscending
    case nameDescending
    case lastChangedNewestFirst
    case lastChangedOldestFirst
    case manualOrder

    static let allCases: [ReaderSidebarSortMode] = [
        .openOrder,
        .nameAscending,
        .nameDescending,
        .lastChangedNewestFirst,
        .lastChangedOldestFirst
    ]
```

Add display name entries for `.manualOrder`:

```swift
    var displayName: String {
        switch self {
        case .openOrder:
            return "Open Order"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .lastChangedNewestFirst:
            return "Last Changed Newest First"
        case .lastChangedOldestFirst:
            return "Last Changed Oldest First"
        case .manualOrder:
            return "Manual"
        }
    }

    var footerLabel: String {
        switch self {
        case .openOrder:
            return "Open Order"
        case .nameAscending:
            return "Name A-Z"
        case .nameDescending:
            return "Name Z-A"
        case .lastChangedNewestFirst:
            return "Newest First"
        case .lastChangedOldestFirst:
            return "Oldest First"
        case .manualOrder:
            return "Manual"
        }
    }
```

In the `isOrderedBefore` method, add a case for `.manualOrder` that preserves original order (it won't normally be called for this mode, but needs to be exhaustive):

```swift
        case .manualOrder:
            return leftIndex < rightIndex
```

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`
Expected: All tests pass (the `.manualOrder` case is not yet used, existing tests should be unaffected).

- [ ] **Step 3: Commit**

```bash
git add minimark/Models/ReaderSidebarSortMode.swift
git commit -m "feat: add .manualOrder case to ReaderSidebarSortMode"
```

---

### Task 2: Add `manualGroupOrder` to `SidebarGroupStateController`

**Files:**
- Modify: `minimark/Stores/SidebarGroupStateController.swift`
- Test: `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`

- [ ] **Step 1: Write failing test for `moveGroup`**

Add to `SidebarGroupStateControllerTests`:

```swift
    @Test @MainActor func moveGroupSetsManualOrderAndSwitchesSortMode() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        controller.moveGroup(from: 2, to: 0)

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(controller.sortMode == .manualOrder)
        let gammaPath = harness.directoryPath(for: "gamma")
        #expect(groups.first?.id == gammaPath)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -20`
Expected: FAIL — `moveGroup(from:to:)` does not exist.

- [ ] **Step 3: Implement `manualGroupOrder` and `moveGroup`**

In `SidebarGroupStateController`, add after `collapsedGroupIDs`:

```swift
    var manualGroupOrder: [String]?
```

Add the `moveGroup` method:

```swift
    func moveGroup(from sourceIndex: Int, to destinationIndex: Int) {
        guard case .grouped(let groups) = computedGrouping else { return }
        var orderedIDs = groups.map(\.id)
        guard sourceIndex < orderedIDs.count else { return }
        let movedID = orderedIDs.remove(at: sourceIndex)
        let adjustedDestination = min(destinationIndex, orderedIDs.count)
        orderedIDs.insert(movedID, at: adjustedDestination)
        manualGroupOrder = orderedIDs
        sortMode = .manualOrder
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/SidebarGroupStateController.swift minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift
git commit -m "feat: add manualGroupOrder and moveGroup to SidebarGroupStateController"
```

---

### Task 3: Apply manual order as post-processing step

**Files:**
- Modify: `minimark/Stores/SidebarGroupStateController.swift`
- Test: `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`

- [ ] **Step 1: Write failing tests for manual order post-processing**

Add to `SidebarGroupStateControllerTests`:

```swift
    @Test @MainActor func manualOrderReordersGroupsAndAppendsNewOnes() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let gammaPath = harness.directoryPath(for: "gamma")
        let alphaPath = harness.directoryPath(for: "alpha")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.manualGroupOrder = [gammaPath, alphaPath]
        controller.sortMode = .manualOrder

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(groups.map(\.id) == [gammaPath, alphaPath, harness.directoryPath(for: "beta")])
    }

    @Test @MainActor func selectingAlgorithmicSortClearsManualOrder() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.manualGroupOrder = [harness.directoryPath(for: "beta")]
        controller.sortMode = .manualOrder

        controller.sortMode = .nameAscending

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(controller.manualGroupOrder == nil)
        #expect(groups.first?.displayName == "alpha")
    }

    @Test @MainActor func manualOrderPreservesPinnedGroupFloat() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        for doc in harness.documents {
            doc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        }

        let betaPath = harness.directoryPath(for: "beta")
        let gammaPath = harness.directoryPath(for: "gamma")
        let alphaPath = harness.directoryPath(for: "alpha")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.pinnedGroupIDs = [betaPath]
        controller.manualGroupOrder = [gammaPath, alphaPath, betaPath]
        controller.sortMode = .manualOrder

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(groups[0].id == betaPath)
        #expect(groups[0].isPinned == true)
        #expect(groups[1].id == gammaPath)
        #expect(groups[2].id == alphaPath)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -30`
Expected: FAIL — manual order is not applied in post-processing.

- [ ] **Step 3: Implement post-processing in `recomputeGrouping()`**

In `SidebarGroupStateController.recomputeGrouping()`, after the line that sets `computedGrouping`, add the post-processing:

```swift
    private func recomputeGrouping(
        sortMode: ReaderSidebarSortMode,
        fileSortMode: ReaderSidebarSortMode,
        pinnedGroupIDs: Set<String>
    ) {
        let sortedDocuments = fileSortMode.sorted(documents) { document in
            ReaderSidebarSortDescriptor(
                displayName: document.readerStore.fileDisplayName,
                lastChangedAt: document.readerStore.fileLastModifiedAt
                    ?? document.readerStore.lastExternalChangeAt
                    ?? document.readerStore.lastRefreshAt
            )
        }

        let directoryOrderSourceDocuments: [ReaderSidebarDocumentController.Document]
        if sortMode == .openOrder {
            directoryOrderSourceDocuments = documents
        } else {
            directoryOrderSourceDocuments = sortedDocuments
        }

        var result = ReaderSidebarGrouping.group(
            sortedDocuments,
            sortMode: sortMode,
            directoryOrderSourceDocuments: directoryOrderSourceDocuments,
            pinnedGroupIDs: pinnedGroupIDs,
            precomputedIndicatorStates: groupIndicatorStates,
            precomputedIndicatorPulseTokens: groupIndicatorPulseTokens
        )

        if sortMode == .manualOrder, let manualOrder = manualGroupOrder,
           case .grouped(let groups) = result {
            result = .grouped(applyManualOrder(manualOrder, to: groups))
        }

        computedGrouping = result
    }
```

Also add the `applyManualOrder` helper method:

```swift
    private func applyManualOrder(_ manualOrder: [String], to groups: [ReaderSidebarGrouping.Group]) -> [ReaderSidebarGrouping.Group] {
        let groupByID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var pinnedManual: [ReaderSidebarGrouping.Group] = []
        var unpinnedManual: [ReaderSidebarGrouping.Group] = []
        var seen = Set<String>()

        for id in manualOrder {
            guard let group = groupByID[id], seen.insert(id).inserted else { continue }
            if group.isPinned {
                pinnedManual.append(group)
            } else {
                unpinnedManual.append(group)
            }
        }

        for group in groups where !seen.contains(group.id) {
            if group.isPinned {
                pinnedManual.append(group)
            } else {
                unpinnedManual.append(group)
            }
        }

        return pinnedManual + unpinnedManual
    }
```

Also update `sortMode`'s `didSet` to clear manual order when switching away from manual:

```swift
    var sortMode: ReaderSidebarSortMode = .lastChangedNewestFirst {
        didSet {
            if sortMode != .manualOrder {
                manualGroupOrder = nil
            }
            recomputeGroupingIfNeeded()
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarGroupStateControllerTests 2>&1 | tail -20`
Expected: All 3 new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/SidebarGroupStateController.swift minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift
git commit -m "feat: apply manual group order as post-processing step"
```

---

### Task 4: Add `manualGroupOrder` to `ReaderFavoriteWorkspaceState` and persistence snapshot

**Files:**
- Modify: `minimark/Models/ReaderFavoriteWorkspaceState.swift`
- Modify: `minimark/Stores/SidebarGroupStateController.swift` (snapshot + apply)
- Modify: `minimark/Views/ReaderWindowRootView.swift` (persistence wiring)
- Test: `minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift`
- Test: `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift`

- [ ] **Step 1: Write failing test for workspace state round-trip with manual order**

Add to `ReaderFavoriteWorkspaceStateTests`:

```swift
    @Test func codableRoundTripPreservesManualGroupOrder() throws {
        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .manualOrder,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 300,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            manualGroupOrder: ["/path/gamma", "/path/alpha"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: data)

        #expect(decoded.manualGroupOrder == ["/path/gamma", "/path/alpha"])
        #expect(decoded.groupSortMode == .manualOrder)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderFavoriteWorkspaceStateTests 2>&1 | tail -20`
Expected: FAIL — `ReaderFavoriteWorkspaceState` does not have `manualGroupOrder` field.

- [ ] **Step 3: Add `manualGroupOrder` to `ReaderFavoriteWorkspaceState`**

In `minimark/Models/ReaderFavoriteWorkspaceState.swift`, add the field:

```swift
    var manualGroupOrder: [String]?
```

Since the struct uses automatic `Codable` synthesis and the new field is optional, existing encoded data (without the key) will decode `manualGroupOrder` as `nil`. Add a custom `CodingKeys` and `init(from:)` to handle backward compatibility explicitly:

```swift
    private enum CodingKeys: String, CodingKey {
        case fileSortMode
        case groupSortMode
        case sidebarPosition
        case sidebarWidth
        case pinnedGroupIDs
        case collapsedGroupIDs
        case lockedAppearance
        case manualGroupOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileSortMode = try container.decode(ReaderSidebarSortMode.self, forKey: .fileSortMode)
        groupSortMode = try container.decode(ReaderSidebarSortMode.self, forKey: .groupSortMode)
        sidebarPosition = try container.decode(ReaderMultiFileDisplayMode.self, forKey: .sidebarPosition)
        sidebarWidth = try container.decode(CGFloat.self, forKey: .sidebarWidth)
        pinnedGroupIDs = try container.decode(Set<String>.self, forKey: .pinnedGroupIDs)
        collapsedGroupIDs = try container.decode(Set<String>.self, forKey: .collapsedGroupIDs)
        lockedAppearance = try container.decodeIfPresent(LockedAppearance.self, forKey: .lockedAppearance)
        manualGroupOrder = try container.decodeIfPresent([String].self, forKey: .manualGroupOrder)
    }
```

Update the `from(settings:)` factory to include `manualGroupOrder: nil`:

```swift
    static func from(
        settings: ReaderSettings,
        pinnedGroupIDs: Set<String>,
        collapsedGroupIDs: Set<String>,
        sidebarWidth: CGFloat
    ) -> ReaderFavoriteWorkspaceState {
        ReaderFavoriteWorkspaceState(
            fileSortMode: settings.sidebarSortMode,
            groupSortMode: settings.sidebarGroupSortMode,
            sidebarPosition: settings.multiFileDisplayMode,
            sidebarWidth: sidebarWidth,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs,
            manualGroupOrder: nil
        )
    }
```

- [ ] **Step 4: Update `SidebarGroupStateController` snapshot and apply**

In `SidebarGroupStateController.WorkspaceStateSnapshot`, add:

```swift
        let manualGroupOrder: [String]?
```

In `persistenceSnapshot`, include it:

```swift
        WorkspaceStateSnapshot(
            sortMode: sortMode,
            fileSortMode: fileSortMode,
            pinnedGroupIDs: pinnedGroupIDs,
            collapsedGroupIDs: collapsedGroupIDs,
            manualGroupOrder: manualGroupOrder
        )
```

In `applyWorkspaceState`, restore it:

```swift
    func applyWorkspaceState(_ state: ReaderFavoriteWorkspaceState) {
        suppressRecompute = true
        sortMode = state.groupSortMode
        fileSortMode = state.fileSortMode
        pinnedGroupIDs = state.pinnedGroupIDs
        collapsedGroupIDs = state.collapsedGroupIDs
        manualGroupOrder = state.manualGroupOrder
        suppressRecompute = false
        recomputeGrouping()
    }
```

- [ ] **Step 5: Update persistence wiring in `ReaderWindowRootView`**

In `ReaderWindowRootView.swift` at line ~270, the `.onChange(of: groupStateController.persistenceSnapshot)` handler needs to sync `manualGroupOrder`:

Add `manualGroupOrder` to the needs-update check:
```swift
                    let needsUpdate =
                        state.pinnedGroupIDs != newSnapshot.pinnedGroupIDs ||
                        state.collapsedGroupIDs != newSnapshot.collapsedGroupIDs ||
                        state.groupSortMode != newSnapshot.sortMode ||
                        state.fileSortMode != newSnapshot.fileSortMode ||
                        state.manualGroupOrder != newSnapshot.manualGroupOrder
```

And in the update block, add:
```swift
                        state.manualGroupOrder = newSnapshot.manualGroupOrder
```

Also update `ReaderWindowRootView+SidebarCommandFlow.swift` in `saveSharedFolderWatchAsFavorite` (around line 62-71) to include `manualGroupOrder`:

```swift
        workspaceState.manualGroupOrder = groupSnapshot.manualGroupOrder
```

- [ ] **Step 6: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add minimark/Models/ReaderFavoriteWorkspaceState.swift minimark/Stores/SidebarGroupStateController.swift minimark/Views/ReaderWindowRootView.swift minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift
git commit -m "feat: persist manual group order in favorites workspace state"
```

---

### Task 5: Add drag-and-drop UI on group headers

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

- [ ] **Step 1: Add drag-and-drop state and handlers to `SidebarGroupListContent`**

Add state properties for tracking drag state:

```swift
    @State private var draggedGroupID: String?
    @State private var dropTargetIndex: Int?
```

- [ ] **Step 2: Modify `groupedSidebarList` to use drag/drop**

In `groupedSidebarList`, wrap each section with drag and drop modifiers. Replace the existing `ForEach` body:

```swift
    @ViewBuilder
    private func groupedSidebarList(
        groups: [ReaderSidebarGrouping.Group],
        currentDate: Date
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    groupedSection(for: group, currentDate: currentDate)
                        .opacity(draggedGroupID == group.id ? 0.4 : 1.0)
                        .onDrag {
                            draggedGroupID = group.id
                            return NSItemProvider(object: group.id as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: SidebarGroupDropDelegate(
                                groups: groups,
                                dropTargetIndex: $dropTargetIndex,
                                draggedGroupID: $draggedGroupID,
                                onDrop: { sourceIndex, destinationIndex in
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        groupState.moveGroup(from: sourceIndex, to: destinationIndex)
                                        dropTargetIndex = nil
                                    }
                                }
                            )
                        )

                    if dropTargetIndex == index && draggedGroupID != nil {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(height: 2)
                            .padding(.horizontal, 12)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
```

- [ ] **Step 3: Add the `SidebarGroupDropDelegate`**

Add this private struct before `SidebarGroupListContent`:

```swift
private struct SidebarGroupDropDelegate: DropDelegate {
    let groups: [ReaderSidebarGrouping.Group]
    @Binding var dropTargetIndex: Int?
    @Binding var draggedGroupID: String?
    let onDrop: (Int, Int) -> Void

    func validateUpdate(info: DropInfo) -> Bool {
        true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedGroupID,
              let sourceIndex = groups.firstIndex(where: { $0.id == draggedID }) else { return }

        let location = info.location
        let midY = location.y

        var targetIndex = 0
        for (index, _) in groups.enumerated() {
            if midY > CGFloat(index) * 50 {
                targetIndex = index
            }
        }

        if targetIndex != sourceIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                dropTargetIndex = targetIndex
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggedID = draggedGroupID,
              let sourceIndex = groups.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = dropTargetIndex else {
            draggedGroupID = nil
            dropTargetIndex = nil
            return false
        }

        onDrop(sourceIndex, targetIndex)
        draggedGroupID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dropTargetIndex = nil
        }
    }
}
```

Note: The `dropEntered` method uses a simplified position heuristic. This will need visual tuning during manual testing. The `50` value approximates the group header height — it should be adjusted to match the actual header height for accurate drop target detection.

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "feat: add drag-and-drop reordering on sidebar group headers"
```

---

### Task 6: Update sort menu to display "Manual" mode correctly

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

- [ ] **Step 1: Update `sidebarGroupSortMenu` to handle manual mode display**

The existing `sidebarGroupSortMenu` iterates `ReaderSidebarSortMode.allCases` which already excludes `.manualOrder` (from Task 1). The label already shows `groupState.sortMode.footerLabel` which returns "Manual" for `.manualOrder`. No structural changes needed.

However, verify the menu works correctly: when `.manualOrder` is active, the menu label shows "Manual", and selecting any algorithmic mode from the dropdown should clear the manual order (already handled by the `sortMode` didSet from Task 3).

Build and manually test:
1. Open a folder watch with 3+ subdirectories
2. Drag a group to reorder
3. Verify the sort menu label changes to "Manual"
4. Click the sort menu and select an algorithmic mode
5. Verify the groups reorder algorithmically and the "Manual" label disappears

- [ ] **Step 2: Commit if any changes were needed**

```bash
git add -u
git commit -m "fix: refine sort menu for manual group order display"
```

(If no changes were needed, skip this step.)

---

### Task 7: Run full test suite and build verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Build in Release configuration**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Release -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED
