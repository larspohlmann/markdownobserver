# Per-Favorite Workspace State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist sidebar sort modes, pinned/collapsed groups, sidebar position, and sidebar width per favorite watch folder, so reopening a favorite fully restores the workspace layout.

**Architecture:** A new `ReaderFavoriteWorkspaceState` struct is embedded in `ReaderFavoriteWatchedFolder`. The sidebar view is refactored to accept bindings for sort modes, pinned groups, collapsed groups, and sidebar width. `ReaderWindowRootView` manages the source of these bindings: from the active favorite's workspace state when one is open, from global settings / ephemeral state otherwise.

**Tech Stack:** SwiftUI, Combine, Foundation (Codable), Swift Testing

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `minimark/Models/ReaderFavoriteWorkspaceState.swift` | Create | New workspace state model |
| `minimark/Models/ReaderFavoriteWatchedFolder.swift` | Modify | Add `workspaceState` property, update CodingKeys/init/decoder/encoder |
| `minimark/Stores/ReaderSettingsStore.swift` | Modify | Add `updateFavoriteWorkspaceState` to `ReaderSettingsWriting` protocol |
| `minimark/Stores/ReaderSettingsStore+Favorites.swift` | Modify | Implement `updateFavoriteWorkspaceState` |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Modify | Accept bindings for sort modes, pinned/collapsed groups, sidebar width |
| `minimark/Views/ReaderWindowRootView.swift` | Modify | Manage workspace state, provide bindings to sidebar |
| `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift` | Modify | Snapshot/restore workspace state on favorite create/open, route sidebar changes |
| `minimarkTests/TestSupport/TestDoubles.swift` | Modify | Update `TestReaderSettingsStore` with new protocol method |
| `minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift` | Create | Tests for the new model |
| `minimarkTests/Core/ReaderFavoriteWatchedFolderTests.swift` | Modify | Add migration tests |
| `minimarkTests/Core/ReaderSettingsStoreFavoritesTests.swift` | Create | Tests for workspace state persistence |

---

### Task 1: Create `ReaderFavoriteWorkspaceState` Model

**Files:**
- Create: `minimark/Models/ReaderFavoriteWorkspaceState.swift`
- Test: `minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift`

- [ ] **Step 1: Write the test file**

```swift
import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderFavoriteWorkspaceStateTests {
    @Test func codableRoundTripPreservesAllFields() throws {
        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .lastChangedNewestFirst,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 300,
            pinnedGroupIDs: ["groupA", "groupB"],
            collapsedGroupIDs: ["groupC"]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ReaderFavoriteWorkspaceState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.fileSortMode == .nameAscending)
        #expect(decoded.groupSortMode == .lastChangedNewestFirst)
        #expect(decoded.sidebarPosition == .sidebarRight)
        #expect(decoded.sidebarWidth == 300)
        #expect(decoded.pinnedGroupIDs == ["groupA", "groupB"])
        #expect(decoded.collapsedGroupIDs == ["groupC"])
    }

    @Test func defaultFactoryUsesGlobalSettingsAndEmptySets() {
        let settings = ReaderSettings.default

        let state = ReaderFavoriteWorkspaceState.from(
            settings: settings,
            pinnedGroupIDs: [],
            collapsedGroupIDs: [],
            sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
        )

        #expect(state.fileSortMode == settings.sidebarSortMode)
        #expect(state.groupSortMode == settings.sidebarGroupSortMode)
        #expect(state.sidebarPosition == settings.multiFileDisplayMode)
        #expect(state.sidebarWidth == ReaderFavoriteWorkspaceState.defaultSidebarWidth)
        #expect(state.pinnedGroupIDs.isEmpty)
        #expect(state.collapsedGroupIDs.isEmpty)
    }

    @Test func snapshotCapturesCurrentValues() {
        let state = ReaderFavoriteWorkspaceState.from(
            settings: ReaderSettings.default,
            pinnedGroupIDs: ["pinned1"],
            collapsedGroupIDs: ["collapsed1", "collapsed2"],
            sidebarWidth: 350
        )

        #expect(state.pinnedGroupIDs == ["pinned1"])
        #expect(state.collapsedGroupIDs == ["collapsed1", "collapsed2"])
        #expect(state.sidebarWidth == 350)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderFavoriteWorkspaceStateTests 2>&1 | tail -20`
Expected: FAIL — `ReaderFavoriteWorkspaceState` does not exist.

- [ ] **Step 3: Create the model**

Create `minimark/Models/ReaderFavoriteWorkspaceState.swift`:

```swift
import Foundation

nonisolated struct ReaderFavoriteWorkspaceState: Equatable, Hashable, Codable, Sendable {
    static let defaultSidebarWidth: CGFloat = 250

    var fileSortMode: ReaderSidebarSortMode
    var groupSortMode: ReaderSidebarSortMode
    var sidebarPosition: ReaderMultiFileDisplayMode
    var sidebarWidth: CGFloat
    var pinnedGroupIDs: Set<String>
    var collapsedGroupIDs: Set<String>

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
            collapsedGroupIDs: collapsedGroupIDs
        )
    }
}
```

- [ ] **Step 4: Add the new file to the Xcode project if needed, then run tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderFavoriteWorkspaceStateTests 2>&1 | tail -20`
Expected: PASS — all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/ReaderFavoriteWorkspaceState.swift minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift
git commit -m "feat: add ReaderFavoriteWorkspaceState model (#50)"
```

---

### Task 2: Integrate `workspaceState` into `ReaderFavoriteWatchedFolder`

**Files:**
- Modify: `minimark/Models/ReaderFavoriteWatchedFolder.swift`
- Modify: `minimarkTests/Core/ReaderFavoriteWatchedFolderTests.swift`

- [ ] **Step 1: Write migration test**

Add to `minimarkTests/Core/ReaderFavoriteWatchedFolderTests.swift`:

```swift
@Test func decodingLegacyFavoriteWithoutWorkspaceStateUsesDefaults() throws {
    let legacyJSON: [String: Any] = [
        "id": UUID().uuidString,
        "name": "Test",
        "folderPath": "/tmp/test",
        "options": [
            "openMode": "watchChangesOnly",
            "scope": "selectedFolderOnly",
            "excludedSubdirectoryPaths": [String]()
        ],
        "openDocumentRelativePaths": ["a.md"],
        "allKnownRelativePaths": ["a.md"],
        "createdAt": Date.now.timeIntervalSinceReferenceDate
    ]

    let data = try JSONSerialization.data(withJSONObject: legacyJSON)
    let decoded = try JSONDecoder().decode(ReaderFavoriteWatchedFolder.self, from: data)

    #expect(decoded.workspaceState.fileSortMode == .openOrder)
    #expect(decoded.workspaceState.groupSortMode == .lastChangedNewestFirst)
    #expect(decoded.workspaceState.sidebarPosition == .sidebarLeft)
    #expect(decoded.workspaceState.sidebarWidth == ReaderFavoriteWorkspaceState.defaultSidebarWidth)
    #expect(decoded.workspaceState.pinnedGroupIDs.isEmpty)
    #expect(decoded.workspaceState.collapsedGroupIDs.isEmpty)
}

@Test func encodingAndDecodingPreservesWorkspaceState() throws {
    let workspaceState = ReaderFavoriteWorkspaceState(
        fileSortMode: .nameDescending,
        groupSortMode: .nameAscending,
        sidebarPosition: .sidebarRight,
        sidebarWidth: 320,
        pinnedGroupIDs: ["group1"],
        collapsedGroupIDs: ["group2"]
    )

    let folder = ReaderFavoriteWatchedFolder(
        name: "Test",
        folderPath: "/tmp/test",
        options: ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        ),
        bookmarkData: nil,
        openDocumentRelativePaths: [],
        allKnownRelativePaths: [],
        createdAt: .now,
        workspaceState: workspaceState
    )

    let data = try JSONEncoder().encode(folder)
    let decoded = try JSONDecoder().decode(ReaderFavoriteWatchedFolder.self, from: data)

    #expect(decoded.workspaceState == workspaceState)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderFavoriteWatchedFolderTests 2>&1 | tail -20`
Expected: FAIL — `workspaceState` property doesn't exist.

- [ ] **Step 3: Add `workspaceState` property and update all code paths**

In `minimark/Models/ReaderFavoriteWatchedFolder.swift`:

1. Add property after `createdAt`:
```swift
var workspaceState: ReaderFavoriteWorkspaceState
```

2. Add to `CodingKeys` enum:
```swift
case workspaceState
```

3. Update the URL-based init (line 37) — add parameter with default:
```swift
init(
    id: UUID = UUID(),
    name: String,
    folderURL: URL,
    options: ReaderFolderWatchOptions,
    openDocumentFileURLs: [URL] = [],
    allKnownRelativePaths: [String] = [],
    createdAt: Date = .now,
    workspaceState: ReaderFavoriteWorkspaceState = .from(
        settings: .default,
        pinnedGroupIDs: [],
        collapsedGroupIDs: [],
        sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
    )
) {
    // ... existing body ...
    self.workspaceState = workspaceState
}
```

4. Update the path-based init (line 65) — add parameter with default:
```swift
init(
    id: UUID = UUID(),
    name: String,
    folderPath: String,
    options: ReaderFolderWatchOptions,
    bookmarkData: Data?,
    openDocumentRelativePaths: [String] = [],
    allKnownRelativePaths: [String] = [],
    createdAt: Date,
    workspaceState: ReaderFavoriteWorkspaceState = .from(
        settings: .default,
        pinnedGroupIDs: [],
        collapsedGroupIDs: [],
        sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
    )
) {
    // ... existing body ...
    self.workspaceState = workspaceState
}
```

5. Update `init(from decoder:)` — decode with fallback for migration:
```swift
workspaceState = try container.decodeIfPresent(
    ReaderFavoriteWorkspaceState.self,
    forKey: .workspaceState
) ?? .from(
    settings: .default,
    pinnedGroupIDs: [],
    collapsedGroupIDs: [],
    sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
)
```

6. Update `encode(to:)` — add encoding:
```swift
try container.encode(workspaceState, forKey: .workspaceState)
```

- [ ] **Step 4: Update all call sites that reconstruct `ReaderFavoriteWatchedFolder`**

In `ReaderSettingsStore+Favorites.swift`, every place that creates a new `ReaderFavoriteWatchedFolder` from an existing one (to update a field) must now pass `workspaceState: existing.workspaceState`. There are 4 locations:

- `updateFavoriteWatchedFolderOpenDocuments` (line 64): add `workspaceState: existing.workspaceState`
- `updateFavoriteWatchedFolderKnownDocuments` (line 100): add `workspaceState: existing.workspaceState`
- `refreshFavoriteWatchedFolderBookmark` (line 157): add `workspaceState: existing.workspaceState`
- `updateFavoriteWatchedFolderBookmarkData` (line 181): add `workspaceState: existing.workspaceState`

In `TestDoubles.swift`, the `TestReaderSettingsStore` also reconstructs favorites in:
- `updateFavoriteWatchedFolderOpenDocuments` (line 235): add `workspaceState: existing.workspaceState`
- `updateFavoriteWatchedFolderKnownDocuments` (line 269): add `workspaceState: existing.workspaceState`

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add minimark/Models/ReaderFavoriteWatchedFolder.swift minimark/Stores/ReaderSettingsStore+Favorites.swift minimarkTests/Core/ReaderFavoriteWatchedFolderTests.swift minimarkTests/TestSupport/TestDoubles.swift
git commit -m "feat: add workspaceState to ReaderFavoriteWatchedFolder with migration (#50)"
```

---

### Task 3: Add Workspace State Update to Settings Store

**Files:**
- Modify: `minimark/Stores/ReaderSettingsStore.swift` (protocol)
- Modify: `minimark/Stores/ReaderSettingsStore+Favorites.swift` (implementation)
- Modify: `minimarkTests/TestSupport/TestDoubles.swift`
- Create: `minimarkTests/Core/ReaderSettingsStoreFavoritesTests.swift`

- [ ] **Step 1: Write the test**

Create `minimarkTests/Core/ReaderSettingsStoreFavoritesTests.swift`:

```swift
import Foundation
import Testing
@testable import minimark

@Suite
struct ReaderSettingsStoreFavoritesTests {
    @Test @MainActor func updateFavoriteWorkspaceStatePersistsChanges() {
        let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        let folderURL = URL(fileURLWithPath: "/tmp/test")
        let options = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: options
        )

        let favoriteID = store.currentSettings.favoriteWatchedFolders.first!.id
        let newState = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameDescending,
            groupSortMode: .nameAscending,
            sidebarPosition: .sidebarRight,
            sidebarWidth: 400,
            pinnedGroupIDs: ["pinned"],
            collapsedGroupIDs: ["collapsed"]
        )

        store.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: newState)

        let updated = store.currentSettings.favoriteWatchedFolders.first!
        #expect(updated.workspaceState == newState)
    }

    @Test @MainActor func updateFavoriteWorkspaceStateNoOpForUnknownID() {
        let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
        let folderURL = URL(fileURLWithPath: "/tmp/test")
        let options = ReaderFolderWatchOptions(
            openMode: .watchChangesOnly,
            scope: .selectedFolderOnly,
            excludedSubdirectoryPaths: []
        )

        store.addFavoriteWatchedFolder(
            name: "Test",
            folderURL: folderURL,
            options: options
        )

        let before = store.currentSettings.favoriteWatchedFolders
        store.updateFavoriteWorkspaceState(
            id: UUID(),
            workspaceState: ReaderFavoriteWorkspaceState(
                fileSortMode: .nameDescending,
                groupSortMode: .nameAscending,
                sidebarPosition: .sidebarRight,
                sidebarWidth: 400,
                pinnedGroupIDs: [],
                collapsedGroupIDs: []
            )
        )

        #expect(store.currentSettings.favoriteWatchedFolders == before)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsStoreFavoritesTests 2>&1 | tail -20`
Expected: FAIL — `updateFavoriteWorkspaceState` doesn't exist.

- [ ] **Step 3: Add to protocol**

In `minimark/Stores/ReaderSettingsStore.swift`, add to the `ReaderSettingsWriting` protocol (after `updateFavoriteWatchedFolderKnownDocuments`):

```swift
func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState)
```

- [ ] **Step 4: Implement on `ReaderSettingsStore`**

In `minimark/Stores/ReaderSettingsStore+Favorites.swift`, add after `reorderFavoriteWatchedFolders`:

```swift
func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
    updateSettings(coalescePersistence: true) { settings in
        guard let index = settings.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
            return
        }

        let existing = settings.favoriteWatchedFolders[index]
        guard existing.workspaceState != workspaceState else {
            return
        }

        settings.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
            id: existing.id,
            name: existing.name,
            folderPath: existing.folderPath,
            options: existing.options,
            bookmarkData: existing.bookmarkData,
            openDocumentRelativePaths: existing.openDocumentRelativePaths,
            allKnownRelativePaths: existing.allKnownRelativePaths,
            createdAt: existing.createdAt,
            workspaceState: workspaceState
        )
    }
}
```

- [ ] **Step 5: Implement on `TestReaderSettingsStore`**

In `minimarkTests/TestSupport/TestDoubles.swift`, add to `TestReaderSettingsStore` (after `clearFavoriteWatchedFolders`):

```swift
func updateFavoriteWorkspaceState(id: UUID, workspaceState: ReaderFavoriteWorkspaceState) {
    var next = subject.value
    guard let index = next.favoriteWatchedFolders.firstIndex(where: { $0.id == id }) else {
        return
    }

    let existing = next.favoriteWatchedFolders[index]
    next.favoriteWatchedFolders[index] = ReaderFavoriteWatchedFolder(
        id: existing.id,
        name: existing.name,
        folderPath: existing.folderPath,
        options: existing.options,
        bookmarkData: existing.bookmarkData,
        openDocumentRelativePaths: existing.openDocumentRelativePaths,
        allKnownRelativePaths: existing.allKnownRelativePaths,
        createdAt: existing.createdAt,
        workspaceState: workspaceState
    )
    recordedFavoriteWatchedFolders = next.favoriteWatchedFolders
    subject.send(next)
}
```

- [ ] **Step 6: Run tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 7: Commit**

```bash
git add minimark/Stores/ReaderSettingsStore.swift minimark/Stores/ReaderSettingsStore+Favorites.swift minimarkTests/TestSupport/TestDoubles.swift minimarkTests/Core/ReaderSettingsStoreFavoritesTests.swift
git commit -m "feat: add updateFavoriteWorkspaceState to settings store (#50)"
```

---

### Task 4: Refactor Sidebar View to Accept Bindings

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`
- Modify: `minimark/Views/ReaderWindowRootView.swift`

This task changes the sidebar view to accept externally managed state via bindings instead of owning sort modes and group state via `@State` / direct `settingsStore` reads. No per-favorite logic yet — just rewiring the plumbing.

- [ ] **Step 1: Update `ReaderSidebarWorkspaceView` to accept bindings**

In `minimark/Views/ReaderSidebarWorkspaceView.swift`:

1. Replace `@State private var collapsedGroupIDs` and `@State private var pinnedGroupIDs` with bindings:
```swift
@Binding var collapsedGroupIDs: Set<String>
@Binding var pinnedGroupIDs: Set<String>
```

2. Add binding parameters for sort modes:
```swift
@Binding var fileSortMode: ReaderSidebarSortMode
@Binding var groupSortMode: ReaderSidebarSortMode
```

3. Add a binding for sidebar width:
```swift
@Binding var sidebarWidth: CGFloat
```

4. Replace `currentFileSidebarSortMode` computed property (line 90-92) with a read from the binding:
```swift
private var currentFileSidebarSortMode: ReaderSidebarSortMode {
    fileSortMode
}
```

5. Replace `currentGroupSidebarSortMode` computed property (line 94-96) with a read from the binding:
```swift
private var currentGroupSidebarSortMode: ReaderSidebarSortMode {
    groupSortMode
}
```

6. Update `sidebarFileSortMenu` (line 337): change `settingsStore.updateSidebarSortMode(mode)` to `fileSortMode = mode`

7. Update `sidebarGroupSortMenu` (line 301): change `settingsStore.updateSidebarGroupSortMode(mode)` to `groupSortMode = mode`

8. Update `sidebarColumn` (around line 210): wrap the sidebar content in a `GeometryReader` overlay to track width, and use the bound width as `idealWidth`:
```swift
.frame(
    minWidth: ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth,
    idealWidth: sidebarWidth,
    maxHeight: .infinity
)
.background(
    GeometryReader { geometry in
        Color.clear.preference(
            key: SidebarWidthPreferenceKey.self,
            value: geometry.size.width
        )
    }
)
.onPreferenceChange(SidebarWidthPreferenceKey.self) { width in
    if width > 0 {
        sidebarWidth = width
    }
}
```

9. Add the preference key (at file level, inside or below the metrics enum):
```swift
private struct SidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
```

10. Remove `@ObservedObject var settingsStore: ReaderSettingsStore` from the view since it's no longer needed (sort modes now come via bindings). Check if `settingsStore` is used for anything else in the view — if not, remove it entirely.

- [ ] **Step 2: Update `ReaderWindowRootView` call site**

In `minimark/Views/ReaderWindowRootView.swift`, add state for the values the sidebar now expects as bindings:

```swift
@State private var sidebarPinnedGroupIDs: Set<String> = []
@State private var sidebarCollapsedGroupIDs: Set<String> = []
@State private var sidebarWidth: CGFloat = ReaderFavoriteWorkspaceState.defaultSidebarWidth
```

Update the `rootContent` view (line 258) to pass the new bindings:

```swift
ReaderSidebarWorkspaceView(
    controller: sidebarDocumentController,
    sidebarPlacement: sidebarPlacement,
    collapsedGroupIDs: $sidebarCollapsedGroupIDs,
    pinnedGroupIDs: $sidebarPinnedGroupIDs,
    fileSortMode: fileSortModeBinding,
    groupSortMode: groupSortModeBinding,
    sidebarWidth: $sidebarWidth,
    detail: { store in
        contentView(for: store)
    },
    // ... rest of closures unchanged
)
```

Add computed binding properties for sort modes that route to global settings (for now — per-favorite routing added in Task 6):

```swift
private var fileSortModeBinding: Binding<ReaderSidebarSortMode> {
    Binding(
        get: { settingsStore.currentSettings.sidebarSortMode },
        set: { settingsStore.updateSidebarSortMode($0) }
    )
}

private var groupSortModeBinding: Binding<ReaderSidebarSortMode> {
    Binding(
        get: { settingsStore.currentSettings.sidebarGroupSortMode },
        set: { settingsStore.updateSidebarGroupSortMode($0) }
    )
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED with zero errors. Sort modes and sidebar state work exactly as before.

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift minimark/Views/ReaderWindowRootView.swift
git commit -m "refactor: sidebar view accepts bindings for sort modes and group state (#50)"
```

---

### Task 5: Track Active Favorite and Route Workspace State

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift`
- Modify: `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift`

This task wires up per-favorite workspace state: snapshot on create, restore on open, persist on change, revert on close.

- [ ] **Step 1: Add active favorite tracking to `ReaderWindowRootView`**

In `minimark/Views/ReaderWindowRootView.swift`, add state:

```swift
@State private var activeFavoriteID: UUID?
@State private var activeFavoriteWorkspaceState: ReaderFavoriteWorkspaceState?
```

- [ ] **Step 2: Update sort mode bindings to route through workspace state**

Replace the `fileSortModeBinding` and `groupSortModeBinding` computed properties:

```swift
private var fileSortModeBinding: Binding<ReaderSidebarSortMode> {
    Binding(
        get: {
            activeFavoriteWorkspaceState?.fileSortMode
                ?? settingsStore.currentSettings.sidebarSortMode
        },
        set: { newValue in
            if activeFavoriteWorkspaceState != nil {
                activeFavoriteWorkspaceState?.fileSortMode = newValue
            } else {
                settingsStore.updateSidebarSortMode(newValue)
            }
        }
    )
}

private var groupSortModeBinding: Binding<ReaderSidebarSortMode> {
    Binding(
        get: {
            activeFavoriteWorkspaceState?.groupSortMode
                ?? settingsStore.currentSettings.sidebarGroupSortMode
        },
        set: { newValue in
            if activeFavoriteWorkspaceState != nil {
                activeFavoriteWorkspaceState?.groupSortMode = newValue
            } else {
                settingsStore.updateSidebarGroupSortMode(newValue)
            }
        }
    )
}
```

- [ ] **Step 3: Override sidebar placement when a favorite is active**

Update the `sidebarPlacement` computed property:

```swift
private var sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement {
    let effectiveMode = activeFavoriteWorkspaceState?.sidebarPosition ?? multiFileDisplayMode
    return effectiveMode.sidebarPlacement
}
```

- [ ] **Step 4: Route sidebar placement toggle through workspace state**

In `ReaderWindowRootView+SidebarCommandFlow.swift`, update `toggleSidebarPlacement()`:

```swift
func toggleSidebarPlacement() {
    if activeFavoriteWorkspaceState != nil {
        let current = activeFavoriteWorkspaceState!.sidebarPosition
        activeFavoriteWorkspaceState?.sidebarPosition = current.toggledSidebarPlacementMode
    } else {
        settingsStore.updateMultiFileDisplayMode(multiFileDisplayMode.toggledSidebarPlacementMode)
    }
}
```

- [ ] **Step 5: Add workspace state persistence on change**

In `minimark/Views/ReaderWindowRootView.swift`, add an `onChange` handler to the root content to persist workspace state changes to the favorite. Put this alongside the other `.onChange` handlers:

```swift
.onChange(of: activeFavoriteWorkspaceState) { _, newState in
    guard let favoriteID = activeFavoriteID, let state = newState else {
        return
    }
    settingsStore.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: state)
}
```

Also connect the pinned/collapsed/width bindings to the workspace state when a favorite is active. Add `onChange` handlers:

```swift
.onChange(of: sidebarPinnedGroupIDs) { _, newValue in
    if activeFavoriteWorkspaceState != nil {
        activeFavoriteWorkspaceState?.pinnedGroupIDs = newValue
    }
}
.onChange(of: sidebarCollapsedGroupIDs) { _, newValue in
    if activeFavoriteWorkspaceState != nil {
        activeFavoriteWorkspaceState?.collapsedGroupIDs = newValue
    }
}
.onChange(of: sidebarWidth) { _, newValue in
    if activeFavoriteWorkspaceState != nil, newValue > 0 {
        activeFavoriteWorkspaceState?.sidebarWidth = newValue
    }
}
```

- [ ] **Step 6: Snapshot workspace state on favorite creation**

In `ReaderWindowRootView+SidebarCommandFlow.swift`, update `saveSharedFolderWatchAsFavorite(name:)`:

```swift
func saveSharedFolderWatchAsFavorite(name: String) {
    guard let session = sharedFolderWatchSession else {
        return
    }
    let workspaceState = ReaderFavoriteWorkspaceState.from(
        settings: settingsStore.currentSettings,
        pinnedGroupIDs: sidebarPinnedGroupIDs,
        collapsedGroupIDs: sidebarCollapsedGroupIDs,
        sidebarWidth: sidebarWidth
    )
    settingsStore.addFavoriteWatchedFolder(
        name: name,
        folderURL: session.folderURL,
        options: session.options,
        openDocumentFileURLs: currentSidebarOpenDocumentFileURLs(),
        workspaceState: workspaceState
    )

    // Set this as the active favorite
    if let created = settingsStore.currentSettings.favoriteWatchedFolders.first(where: {
        $0.matches(folderPath: ReaderFileRouting.normalizedFileURL(session.folderURL).path, options: session.options)
    }) {
        activeFavoriteID = created.id
        activeFavoriteWorkspaceState = created.workspaceState
    }
}
```

This requires updating `addFavoriteWatchedFolder` to accept a `workspaceState` parameter. In `ReaderSettingsStore.swift`, update the protocol method and implementations:

Protocol (`ReaderSettingsWriting`):
```swift
func addFavoriteWatchedFolder(
    name: String,
    folderURL: URL,
    options: ReaderFolderWatchOptions,
    openDocumentFileURLs: [URL],
    workspaceState: ReaderFavoriteWorkspaceState
)
```

`ReaderSettingsStore+Favorites.swift`:
```swift
func addFavoriteWatchedFolder(
    name: String,
    folderURL: URL,
    options: ReaderFolderWatchOptions,
    openDocumentFileURLs: [URL] = [],
    workspaceState: ReaderFavoriteWorkspaceState = .from(
        settings: .default,
        pinnedGroupIDs: [],
        collapsedGroupIDs: [],
        sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
    )
) {
    updateSettings { settings in
        settings.favoriteWatchedFolders = ReaderFavoriteHistory.insertingUniqueFavorite(
            name: name,
            folderURL: folderURL,
            options: options,
            openDocumentFileURLs: openDocumentFileURLs,
            workspaceState: workspaceState,
            into: settings.favoriteWatchedFolders
        )
    }
}
```

Also update `ReaderFavoriteHistory.insertingUniqueFavorite` to accept and pass through `workspaceState`. And update `TestReaderSettingsStore.addFavoriteWatchedFolder` to accept the new parameter.

- [ ] **Step 7: Restore workspace state on favorite open**

In `ReaderWindowRootView+SidebarCommandFlow.swift`, update `startFavoriteWatch(_ entry:)`:

```swift
func startFavoriteWatch(_ entry: ReaderFavoriteWatchedFolder) {
    // Store workspace state for this favorite
    activeFavoriteID = entry.id
    activeFavoriteWorkspaceState = entry.workspaceState

    // Apply workspace state to sidebar bindings
    sidebarPinnedGroupIDs = entry.workspaceState.pinnedGroupIDs
    sidebarCollapsedGroupIDs = entry.workspaceState.collapsedGroupIDs
    sidebarWidth = entry.workspaceState.sidebarWidth

    let resolvedURL = settingsStore.resolvedFavoriteWatchedFolderURL(for: entry)
    startWatchingFolder(
        folderURL: resolvedURL,
        options: entry.options,
        performInitialAutoOpen: false
    )

    let restoredFileURLs = entry.resolvedOpenDocumentFileURLs(relativeTo: resolvedURL)
    if let session = sharedFolderWatchSession,
       !restoredFileURLs.isEmpty {
        openSidebarDocumentsBurst(
            at: restoredFileURLs,
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )
    }

    syncSharedFavoriteOpenDocumentsIfNeeded()

    if entry.options.openMode == .openAllMarkdownFiles {
        discoverNewFilesForFavorite(entry, resolvedFolderURL: resolvedURL)
    }
}
```

- [ ] **Step 8: Clear workspace state when folder watch ends**

Find where the folder watch session is cleared (when closing the watched folder or switching to a different one). Add logic to reset:

```swift
activeFavoriteID = nil
activeFavoriteWorkspaceState = nil
sidebarPinnedGroupIDs = []
sidebarCollapsedGroupIDs = []
sidebarWidth = ReaderFavoriteWorkspaceState.defaultSidebarWidth
```

This should happen wherever `sharedFolderWatchSession` is set to `nil` or when a new non-favorite watch starts.

- [ ] **Step 9: Build and verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 10: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 11: Commit**

```bash
git add minimark/Views/ReaderWindowRootView.swift minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift minimark/Stores/ReaderSettingsStore.swift minimark/Stores/ReaderSettingsStore+Favorites.swift minimark/Models/ReaderFavoriteWatchedFolder.swift minimarkTests/TestSupport/TestDoubles.swift
git commit -m "feat: workspace state snapshot/restore/persist for favorites (#50)"
```

---

### Task 6: Update `ReaderStore+FavoritesFlow` for Consistency

**Files:**
- Modify: `minimark/Stores/Coordination/ReaderStore+FavoritesFlow.swift`

The `ReaderStore` extension also has `saveFolderWatchAsFavorite` and `startFavoriteWatch` methods. These are the non-view versions. Update them to support workspace state for API consistency (they may be called from keyboard shortcuts or other paths).

- [ ] **Step 1: Update `saveFolderWatchAsFavorite` on ReaderStore**

```swift
func saveFolderWatchAsFavorite(
    name: String,
    workspaceState: ReaderFavoriteWorkspaceState = .from(
        settings: .default,
        pinnedGroupIDs: [],
        collapsedGroupIDs: [],
        sidebarWidth: ReaderFavoriteWorkspaceState.defaultSidebarWidth
    )
) {
    guard let session = activeFolderWatchSession else {
        return
    }

    settingsStore.addFavoriteWatchedFolder(
        name: name,
        folderURL: session.folderURL,
        options: session.options,
        openDocumentFileURLs: fileURL.map { [$0] } ?? [],
        workspaceState: workspaceState
    )
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add minimark/Stores/Coordination/ReaderStore+FavoritesFlow.swift
git commit -m "feat: pass workspace state through ReaderStore favorites flow (#50)"
```

---

### Task 7: Integration Tests

**Files:**
- Modify: `minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift`

- [ ] **Step 1: Add round-trip integration tests**

Add to `ReaderFavoriteWorkspaceStateTests.swift`:

```swift
@Test func favoriteWithWorkspaceStateRoundTripsViaReaderSettings() throws {
    let workspaceState = ReaderFavoriteWorkspaceState(
        fileSortMode: .lastChangedOldestFirst,
        groupSortMode: .nameDescending,
        sidebarPosition: .sidebarRight,
        sidebarWidth: 275,
        pinnedGroupIDs: ["dir1", "dir2"],
        collapsedGroupIDs: ["dir3"]
    )

    let favorite = ReaderFavoriteWatchedFolder(
        name: "Integration Test",
        folderPath: "/tmp/integration",
        options: ReaderFolderWatchOptions(
            openMode: .openAllMarkdownFiles,
            scope: .includeSubfolders,
            excludedSubdirectoryPaths: []
        ),
        bookmarkData: nil,
        openDocumentRelativePaths: ["a.md", "b.md"],
        allKnownRelativePaths: ["a.md", "b.md", "c.md"],
        createdAt: .now,
        workspaceState: workspaceState
    )

    var settings = ReaderSettings.default
    settings.favoriteWatchedFolders = [favorite]

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)

    let restoredFavorite = decoded.favoriteWatchedFolders.first!
    #expect(restoredFavorite.workspaceState == workspaceState)
    #expect(restoredFavorite.workspaceState.fileSortMode == .lastChangedOldestFirst)
    #expect(restoredFavorite.workspaceState.pinnedGroupIDs == ["dir1", "dir2"])
    #expect(restoredFavorite.workspaceState.sidebarWidth == 275)
}

@Test @MainActor func workspaceStateUpdatePersistsAndRoundTrips() {
    let store = TestReaderSettingsStore(autoRefreshOnExternalChange: false)
    let folderURL = URL(fileURLWithPath: "/tmp/roundtrip")
    let options = ReaderFolderWatchOptions(
        openMode: .watchChangesOnly,
        scope: .selectedFolderOnly,
        excludedSubdirectoryPaths: []
    )

    store.addFavoriteWatchedFolder(
        name: "RoundTrip",
        folderURL: folderURL,
        options: options
    )

    let favoriteID = store.currentSettings.favoriteWatchedFolders.first!.id

    // Initial workspace state should have defaults
    let initial = store.currentSettings.favoriteWatchedFolders.first!.workspaceState
    #expect(initial.pinnedGroupIDs.isEmpty)
    #expect(initial.collapsedGroupIDs.isEmpty)

    // Update workspace state
    var updated = initial
    updated.fileSortMode = .nameAscending
    updated.pinnedGroupIDs = ["group1"]
    updated.sidebarWidth = 300

    store.updateFavoriteWorkspaceState(id: favoriteID, workspaceState: updated)

    // Verify persisted
    let persisted = store.currentSettings.favoriteWatchedFolders.first!
    #expect(persisted.workspaceState.fileSortMode == .nameAscending)
    #expect(persisted.workspaceState.pinnedGroupIDs == ["group1"])
    #expect(persisted.workspaceState.sidebarWidth == 300)
    #expect(persisted.name == "RoundTrip") // other fields unchanged
}
```

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 3: Commit**

```bash
git add minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift
git commit -m "test: add integration tests for workspace state round-trip (#50)"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: ALL PASS.

- [ ] **Step 2: Clean build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug clean && xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Verify no regressions in existing favorites behavior**

Manually verify (or have the reviewer verify):
- Opening a non-favorite folder watch still works normally
- Sort modes still persist globally when no favorite is active
- Creating and reopening a favorite restores all workspace state
- Changing sort modes while a favorite is active updates only the favorite
- Closing a favorite reverts to global settings
