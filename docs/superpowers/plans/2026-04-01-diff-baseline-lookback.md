# Configurable Diff Baseline Lookback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the diff baseline lookback time user-configurable with a default of 2 minutes, exposed in the Settings UI.

**Architecture:** Add a `DiffBaselineLookback` enum to Models, wire it into `ReaderSettings` as a persisted property, expose it in `ReaderSettingsView` as a picker, and pass the value through to `ReaderFolderWatchAutoOpenPlanner` at construction time.

**Tech Stack:** Swift, SwiftUI, Combine, Swift Testing

---

### Task 1: Create `DiffBaselineLookback` enum

**Files:**
- Create: `minimark/Models/DiffBaselineLookback.swift`
- Test: `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`:

```swift
@Test func diffBaselineLookbackTimeIntervalValues() {
    #expect(DiffBaselineLookback.tenSeconds.timeInterval == 10)
    #expect(DiffBaselineLookback.thirtySeconds.timeInterval == 30)
    #expect(DiffBaselineLookback.oneMinute.timeInterval == 60)
    #expect(DiffBaselineLookback.twoMinutes.timeInterval == 120)
    #expect(DiffBaselineLookback.fiveMinutes.timeInterval == 300)
    #expect(DiffBaselineLookback.tenMinutes.timeInterval == 600)
}

@Test func diffBaselineLookbackDisplayNames() {
    #expect(DiffBaselineLookback.tenSeconds.displayName == "10 seconds")
    #expect(DiffBaselineLookback.thirtySeconds.displayName == "30 seconds")
    #expect(DiffBaselineLookback.oneMinute.displayName == "1 minute")
    #expect(DiffBaselineLookback.twoMinutes.displayName == "2 minutes")
    #expect(DiffBaselineLookback.fiveMinutes.displayName == "5 minutes")
    #expect(DiffBaselineLookback.tenMinutes.displayName == "10 minutes")
}

@Test func diffBaselineLookbackCodableRoundTrip() throws {
    for lookback in DiffBaselineLookback.allCases {
        let data = try JSONEncoder().encode(lookback)
        let decoded = try JSONDecoder().decode(DiffBaselineLookback.self, from: data)
        #expect(decoded == lookback)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests 2>&1 | tail -20`
Expected: Build failure — `DiffBaselineLookback` not found.

- [ ] **Step 3: Create the enum**

Create `minimark/Models/DiffBaselineLookback.swift`:

```swift
import Foundation

nonisolated enum DiffBaselineLookback: String, CaseIterable, Codable, Sendable, Identifiable {
    case tenSeconds
    case thirtySeconds
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case tenMinutes

    nonisolated var id: String { rawValue }

    var timeInterval: TimeInterval {
        switch self {
        case .tenSeconds: return 10
        case .thirtySeconds: return 30
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        }
    }

    var displayName: String {
        switch self {
        case .tenSeconds: return "10 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        }
    }
}
```

Add the new file to the Xcode project's minimark target. It follows the same pattern as `ReaderMultiFileDisplayMode` and `ReaderSidebarSortMode`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests 2>&1 | tail -20`
Expected: All three new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/DiffBaselineLookback.swift minimarkTests/Core/ReaderSettingsAndModelsTests.swift minimark.xcodeproj
git commit -m "feat: add DiffBaselineLookback enum with presets (#58)"
```

---

### Task 2: Add `diffBaselineLookback` to `ReaderSettings` and `ReaderSettingsStore`

**Files:**
- Modify: `minimark/Stores/ReaderSettingsStore.swift`
- Test: `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`:

```swift
@Test func readerSettingsDecodesDefaultLookbackWhenKeyMissing() throws {
    // Encode current default settings, then strip the key to simulate old data
    var settingsDict = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(ReaderSettings.default)
    ) as! [String: Any]
    settingsDict.removeValue(forKey: "diffBaselineLookback")
    let data = try JSONSerialization.data(withJSONObject: settingsDict)

    let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)
    #expect(decoded.diffBaselineLookback == .twoMinutes)
}

@Test func readerSettingsCodableRoundTripPreservesDiffBaselineLookback() throws {
    var settings = ReaderSettings.default
    settings.diffBaselineLookback = .fiveMinutes

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)
    #expect(decoded.diffBaselineLookback == .fiveMinutes)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests 2>&1 | tail -20`
Expected: Build failure — `diffBaselineLookback` not a member of `ReaderSettings`.

- [ ] **Step 3: Add field to `ReaderSettings`**

In `minimark/Stores/ReaderSettingsStore.swift`, make these changes:

Add the property to `ReaderSettings` struct (after `trustedImageFolders`):
```swift
var diffBaselineLookback: DiffBaselineLookback
```

Add to `CodingKeys`:
```swift
case diffBaselineLookback
```

Add to `init(...)` parameter list (with default):
```swift
diffBaselineLookback: DiffBaselineLookback = .twoMinutes
```

Add assignment in `init(...)` body:
```swift
self.diffBaselineLookback = diffBaselineLookback
```

Add to `init(from decoder:)` (after `trustedImageFolders` line):
```swift
diffBaselineLookback = try container.decodeIfPresent(DiffBaselineLookback.self, forKey: .diffBaselineLookback) ?? .twoMinutes
```

Add to `static let default`:
```swift
diffBaselineLookback: .twoMinutes
```

- [ ] **Step 4: Add update method to store**

Add to `ReaderSettingsWriting` protocol:
```swift
func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback)
```

Add implementation in `ReaderSettingsStore` (after `updateSidebarGroupSortMode`):
```swift
func updateDiffBaselineLookback(_ lookback: DiffBaselineLookback) {
    updateSettings(coalescePersistence: true) { settings in
        settings.diffBaselineLookback = lookback
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests 2>&1 | tail -20`
Expected: Both new tests PASS.

- [ ] **Step 6: Commit**

```bash
git add minimark/Stores/ReaderSettingsStore.swift minimarkTests/Core/ReaderSettingsAndModelsTests.swift
git commit -m "feat: add diffBaselineLookback to ReaderSettings with 2-minute default (#58)"
```

---

### Task 3: Add "Change Highlighting" section to Settings UI

**Files:**
- Modify: `minimark/Views/ReaderSettingsView.swift`

- [ ] **Step 1: Add the new section**

In `ReaderSettingsView`, add a new section between the "Window Layout" section (ends at line 82) and the "Notifications" section (starts at line 84):

```swift
Section("Change Highlighting") {
    Picker("Diff lookback", selection: Binding(
        get: { settings.diffBaselineLookback },
        set: { settingsStore.updateDiffBaselineLookback($0) }
    )) {
        ForEach(DiffBaselineLookback.allCases) { lookback in
            Text(lookback.displayName).tag(lookback)
        }
    }

    Text("How far back MarkdownObserver looks for the previous version of a file when highlighting changes. Longer values show more accumulated changes, which works better with AI tools that make many incremental edits.")
        .font(.callout)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/ReaderSettingsView.swift
git commit -m "feat: add Change Highlighting section to Settings UI (#58)"
```

---

### Task 4: Wire setting to planner construction sites

**Files:**
- Modify: `minimark/Stores/ReaderStore.swift:127-158` (two convenience inits)
- Modify: `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift:68-76` (convenience init)

- [ ] **Step 1: Update `ReaderStore` convenience init (no settingsStore param)**

In `minimark/Stores/ReaderStore.swift`, in the `convenience init()` at line 127, change:

```swift
folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
```

to:

```swift
folderWatchAutoOpenPlanner: {
    let store = ReaderSettingsStore()
    // Note: this init creates its own settingsStore, so read from it
    return ReaderFolderWatchAutoOpenPlanner(
        minimumDiffBaselineAge: store.currentSettings.diffBaselineLookback.timeInterval
    )
}(),
```

Wait — this init already creates `ReaderSettingsStore()` inline (line 134). But the planner is constructed before settingsStore is assigned. The cleanest fix: extract the settings store into a local, pass it to both.

Replace the entire `convenience init()` body (lines 127-142):

```swift
convenience init() {
    let settler = ReaderAutoOpenSettler(settlingInterval: 1.0)
    let settingsStore = ReaderSettingsStore()
    self.init(
        renderer: MarkdownRenderingService(),
        differ: ChangedRegionDiffer(),
        fileWatcher: FileChangeWatcher(),
        folderWatcher: FolderChangeWatcher(),
        settingsStore: settingsStore,
        securityScope: SecurityScopedResourceAccess(),
        fileActions: ReaderFileActionService(),
        systemNotifier: ReaderSystemNotifier.shared,
        folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
            minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
        ),
        settler: settler
    )
    configureSettler(settler)
}
```

- [ ] **Step 2: Update `ReaderStore` convenience init (with settingsStore param)**

In `minimark/Stores/ReaderStore.swift`, in the `convenience init(settingsStore:)` at line 144, change:

```swift
folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(),
```

to:

```swift
folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
    minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
),
```

- [ ] **Step 3: Update `ReaderFolderWatchController` convenience init**

In `minimark/Stores/ReaderSidebarFolderWatchOwnership.swift`, in the `convenience init(settingsStore:)` at line 68, change:

```swift
folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner()
```

to:

```swift
folderWatchAutoOpenPlanner: ReaderFolderWatchAutoOpenPlanner(
    minimumDiffBaselineAge: settingsStore.currentSettings.diffBaselineLookback.timeInterval
)
```

- [ ] **Step 4: Build and run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`
Expected: All tests PASS. No regressions — tests that use `ReaderFolderWatchAutoOpenPlanner()` directly still use the default init (which defaults to 10s), so they are unaffected.

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/ReaderStore.swift minimark/Stores/ReaderSidebarFolderWatchOwnership.swift
git commit -m "feat: wire diffBaselineLookback setting to planner construction (#58)"
```
