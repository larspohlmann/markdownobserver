# Settings Rendering Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate UI freezes when changing theme, font size, or syntax theme by reducing renders from 3xN to 1 per settings change.

**Architecture:** Coalesce `WindowAppearanceController`'s three `@Published` properties into one `LockedAppearance` struct, render only the selected document on appearance change (lazy-render others on selection), skip deferred documents, and cache CSS generation.

**Tech Stack:** Swift, SwiftUI, Combine

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `minimark/Stores/WindowAppearanceController.swift` | Modify | Coalesce 3 `@Published` into 1 `@Published var effectiveAppearance` |
| `minimark/Views/ReaderWindowRootView.swift` | Modify | Collapse 3 `.onChange` to 1; render only selected doc; lazy-render on selection |
| `minimark/Stores/ReaderStore.swift` | Modify | Add `needsAppearanceRender` flag; clear on render |
| `minimark/Support/ReaderCSSFactory.swift` | Modify | Add last-result CSS cache |
| `minimarkTests/Core/WindowAppearanceControllerTests.swift` | Modify | Update tests for new single-property API |
| `minimarkTests/Rendering/ReaderCSSFactoryTests.swift` | Create | Test CSS cache hit/miss |
| `minimarkTests/ReaderStore/ReaderStoreAppearanceRenderTests.swift` | Create | Test `needsAppearanceRender` flag lifecycle |

---

### Task 1: Coalesce WindowAppearanceController to single published property

**Files:**
- Modify: `minimark/Stores/WindowAppearanceController.swift`
- Modify: `minimarkTests/Core/WindowAppearanceControllerTests.swift`

- [ ] **Step 1: Update existing tests to use `effectiveAppearance` struct**

In `minimarkTests/Core/WindowAppearanceControllerTests.swift`, update all assertions that read individual properties to read from `effectiveAppearance`. The computed convenience properties (`effectiveTheme`, `effectiveFontSize`, `effectiveSyntaxTheme`) will still exist, so existing assertions will compile — but add one new test that verifies a single settings change produces exactly one `objectWillChange` notification:

```swift
func testSingleSettingsChangeProducesOneObjectWillChange() {
    let controller = WindowAppearanceController(settingsStore: settingsStore)
    var changeCount = 0
    let cancellable = controller.objectWillChange.sink { _ in changeCount += 1 }

    settingsStore.updateTheme(.newspaper)
    drainMainQueue()

    XCTAssertEqual(changeCount, 1)
    _ = cancellable
}
```

Add this test after the existing "Unlocked propagation" section (after line 67).

- [ ] **Step 2: Run tests to verify the new test fails**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/WindowAppearanceControllerTests/testSingleSettingsChangeProducesOneObjectWillChange 2>&1 | tail -20
```

Expected: FAIL — currently three separate `@Published` assignments produce 3 `objectWillChange` notifications.

- [ ] **Step 3: Refactor WindowAppearanceController**

In `minimark/Stores/WindowAppearanceController.swift`, replace the three `@Published` properties with one struct and add computed accessors:

Replace lines 8-10:
```swift
@Published private(set) var effectiveTheme: ReaderThemeKind
@Published private(set) var effectiveFontSize: Double
@Published private(set) var effectiveSyntaxTheme: SyntaxThemeKind
```

With:
```swift
@Published private(set) var effectiveAppearance: LockedAppearance

var effectiveTheme: ReaderThemeKind { effectiveAppearance.readerTheme }
var effectiveFontSize: Double { effectiveAppearance.baseFontSize }
var effectiveSyntaxTheme: SyntaxThemeKind { effectiveAppearance.syntaxTheme }
```

Update the initializer (lines 24-27):
```swift
let current = settingsStore.currentSettings
self.effectiveAppearance = LockedAppearance(
    readerTheme: current.readerTheme,
    baseFontSize: current.baseFontSize,
    syntaxTheme: current.syntaxTheme
)
```

Update the Combine sink (lines 32-42). Replace the three conditional assignments with a single struct comparison and assignment:
```swift
.sink { [weak self] settings in
    guard let self, !self.isLocked else { return }
    let newAppearance = LockedAppearance(
        readerTheme: settings.readerTheme,
        baseFontSize: settings.baseFontSize,
        syntaxTheme: settings.syntaxTheme
    )
    if self.effectiveAppearance != newAppearance {
        self.effectiveAppearance = newAppearance
    }
}
```

Update `unlock()` (lines 65-68):
```swift
let current = settingsStore.currentSettings
effectiveAppearance = LockedAppearance(
    readerTheme: current.readerTheme,
    baseFontSize: current.baseFontSize,
    syntaxTheme: current.syntaxTheme
)
```

Update `restore(from:)` (lines 72-74):
```swift
func restore(from appearance: LockedAppearance) {
    effectiveAppearance = appearance
    // ... rest unchanged
```

Update `lockedAppearance` computed property (lines 83-90):
```swift
var lockedAppearance: LockedAppearance? {
    guard isLocked else { return nil }
    return effectiveAppearance
}
```

- [ ] **Step 4: Run all WindowAppearanceController tests**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/WindowAppearanceControllerTests 2>&1 | tail -20
```

Expected: ALL PASS including the new `testSingleSettingsChangeProducesOneObjectWillChange`.

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/WindowAppearanceController.swift minimarkTests/Core/WindowAppearanceControllerTests.swift
git commit -m "refactor: coalesce WindowAppearanceController to single published appearance (#136)"
```

---

### Task 2: Collapse `.onChange` handlers in ReaderWindowRootView

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift`

- [ ] **Step 1: Replace three `.onChange` handlers with one**

In `minimark/Views/ReaderWindowRootView.swift`, replace lines 279-287:
```swift
.onChange(of: appearanceController.effectiveTheme) { _, _ in
    reapplyAppearance()
}
.onChange(of: appearanceController.effectiveFontSize) { _, _ in
    reapplyAppearance()
}
.onChange(of: appearanceController.effectiveSyntaxTheme) { _, _ in
    reapplyAppearance()
}
```

With:
```swift
.onChange(of: appearanceController.effectiveAppearance) { _, _ in
    reapplyAppearance()
}
```

- [ ] **Step 2: Update `reapplyAppearance()` to pass the struct**

In the same file, update `reapplyAppearance()` at line 300 to read from the struct:

```swift
private func reapplyAppearance() {
    Task { @MainActor in
        let appearance = appearanceController.effectiveAppearance
        for document in sidebarDocumentController.documents {
            try? document.readerStore.renderWithAppearance(
                theme: appearance.readerTheme,
                baseFontSize: appearance.baseFontSize,
                syntaxTheme: appearance.syntaxTheme
            )
        }
    }
}
```

- [ ] **Step 3: Update `onToggleAppearanceLock` to use struct**

In the same file, update the lock branch around line 494 to read from the struct:

```swift
appearanceController.lock()
let appearance = appearanceController.effectiveAppearance
for document in sidebarDocumentController.documents {
    document.readerStore.setAppearanceOverride(
        theme: appearance.readerTheme,
        baseFontSize: appearance.baseFontSize,
        syntaxTheme: appearance.syntaxTheme
    )
}
```

- [ ] **Step 4: Update `effectiveReaderTheme` reference**

At line 466, update:
```swift
effectiveReaderTheme: appearanceController.effectiveTheme
```
to:
```swift
effectiveReaderTheme: appearanceController.effectiveAppearance.readerTheme
```

- [ ] **Step 5: Build to verify compilation**

Run:
```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add minimark/Views/ReaderWindowRootView.swift
git commit -m "refactor: collapse three appearance .onChange handlers into one (#136)"
```

---

### Task 3: Add `needsAppearanceRender` flag and lazy rendering

**Files:**
- Modify: `minimark/Stores/ReaderStore.swift`
- Modify: `minimark/Views/ReaderWindowRootView.swift`
- Create: `minimarkTests/ReaderStore/ReaderStoreAppearanceRenderTests.swift`

- [ ] **Step 1: Write tests for the `needsAppearanceRender` flag**

Create `minimarkTests/ReaderStore/ReaderStoreAppearanceRenderTests.swift`:

```swift
import XCTest
@testable import minimark

@MainActor
final class ReaderStoreAppearanceRenderTests: XCTestCase {

    func testSetAppearanceOverrideSetsNeedsAppearanceRender() {
        let store = TestReaderStoreFactory.makeStore()
        XCTAssertFalse(store.needsAppearanceRender)

        store.setAppearanceOverride(theme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)

        XCTAssertTrue(store.needsAppearanceRender)
    }

    func testRenderWithAppearanceClearsNeedsAppearanceRender() throws {
        let store = TestReaderStoreFactory.makeReadyStore()
        store.setAppearanceOverride(theme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)
        XCTAssertTrue(store.needsAppearanceRender)

        try store.renderWithAppearance(theme: .newspaper, baseFontSize: 20, syntaxTheme: .nord)

        XCTAssertFalse(store.needsAppearanceRender)
    }
}
```

Note: `TestReaderStoreFactory` is used in existing tests — check the `TestSupport/` directory for the exact factory method names. If the factory uses different names (e.g. `makeDefault()`, `makeWithOpenDocument()`), adapt accordingly. The key requirement is: one store with no document open (for the first test) and one store with a loaded document (for the second test, since `renderWithAppearance` calls `renderCurrentMarkdown` which needs source markdown).

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderStoreAppearanceRenderTests 2>&1 | tail -20
```

Expected: FAIL — `needsAppearanceRender` property does not exist yet.

- [ ] **Step 3: Add `needsAppearanceRender` to ReaderStore**

In `minimark/Stores/ReaderStore.swift`, add a property near the other document state properties (around line 58, near `appearanceOverride`):

```swift
private(set) var needsAppearanceRender = false
```

In `setAppearanceOverride` (line 525-534), add at the end of the method body:
```swift
needsAppearanceRender = true
```

In `renderWithAppearance` (line 510-523), add after the `try renderCurrentMarkdown()` call:
```swift
needsAppearanceRender = false
```

Also clear it in `renderCurrentMarkdown()` (around line 567, after the `document.renderedHTMLDocument = ...` assignment):
```swift
needsAppearanceRender = false
```

- [ ] **Step 4: Run the new tests**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderStoreAppearanceRenderTests 2>&1 | tail -20
```

Expected: PASS

- [ ] **Step 5: Update `reapplyAppearance()` for lazy rendering**

In `minimark/Views/ReaderWindowRootView.swift`, replace `reapplyAppearance()` with:

```swift
private func reapplyAppearance() {
    Task { @MainActor in
        let appearance = appearanceController.effectiveAppearance
        for document in sidebarDocumentController.documents {
            let store = document.readerStore
            guard store.hasOpenDocument else { continue }

            if document.id == sidebarDocumentController.selectedDocumentID {
                try? store.renderWithAppearance(
                    theme: appearance.readerTheme,
                    baseFontSize: appearance.baseFontSize,
                    syntaxTheme: appearance.syntaxTheme
                )
            } else {
                store.setAppearanceOverride(
                    theme: appearance.readerTheme,
                    baseFontSize: appearance.baseFontSize,
                    syntaxTheme: appearance.syntaxTheme
                )
            }
        }
    }
}
```

- [ ] **Step 6: Add lazy render on document selection**

In the same file, find the existing `.onChange(of: sidebarDocumentController.selectedDocumentID)` handler at line 202:

```swift
.onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
    applyWindowTitlePresentation()
}
```

Add the lazy render call:

```swift
.onChange(of: sidebarDocumentController.selectedDocumentID) { _, _ in
    applyWindowTitlePresentation()
    renderSelectedDocumentIfNeeded()
}
```

Add the new private method near `reapplyAppearance()`:

```swift
private func renderSelectedDocumentIfNeeded() {
    guard let document = sidebarDocumentController.selectedDocument else { return }
    let store = document.readerStore
    guard store.needsAppearanceRender, store.hasOpenDocument else { return }
    let appearance = appearanceController.effectiveAppearance
    try? store.renderWithAppearance(
        theme: appearance.readerTheme,
        baseFontSize: appearance.baseFontSize,
        syntaxTheme: appearance.syntaxTheme
    )
}
```

- [ ] **Step 7: Build and run full test suite**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30
```

Expected: ALL PASS

- [ ] **Step 8: Commit**

```bash
git add minimark/Stores/ReaderStore.swift minimark/Views/ReaderWindowRootView.swift minimarkTests/ReaderStore/ReaderStoreAppearanceRenderTests.swift
git commit -m "feat: render only selected document on appearance change, lazy-render others (#136)"
```

---

### Task 4: Cache CSS generation

**Files:**
- Modify: `minimark/Support/ReaderCSSThemeGenerator.swift`
- Create: `minimarkTests/Rendering/ReaderCSSFactoryTests.swift`

- [ ] **Step 1: Write CSS cache tests**

Create `minimarkTests/Rendering/ReaderCSSFactoryTests.swift`:

```swift
import XCTest
@testable import minimark

final class ReaderCSSFactoryCacheTests: XCTestCase {

    func testSameInputsReturnCachedCSS() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertEqual(css1, css2)
        XCTAssertTrue(css1 == css2) // same content
    }

    func testDifferentThemeInvalidatesCache() {
        let theme1 = ReaderThemeKind.blackOnWhite.themeDefinition
        let theme2 = ReaderThemeKind.newspaper.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme1, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme2, syntaxTheme: .monokai, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentFontSizeInvalidatesCache() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 20)

        XCTAssertNotEqual(css1, css2)
    }

    func testDifferentSyntaxThemeInvalidatesCache() {
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css1 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 15)
        let css2 = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: .dracula, baseFontSize: 15)

        XCTAssertNotEqual(css1, css2)
    }
}
```

- [ ] **Step 2: Run tests — they should pass already (no cache yet, but correctness holds)**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderCSSFactoryCacheTests 2>&1 | tail -20
```

Expected: PASS (the tests verify correctness, not caching behavior — they establish the baseline).

- [ ] **Step 3: Add static cache to ReaderCSSThemeGenerator**

In `minimark/Support/ReaderCSSThemeGenerator.swift`, add a static cache. Replace the current method:

```swift
enum ReaderCSSThemeGenerator {
    private static var cachedInput: (theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double)?
    private static var cachedCSS: String?

    static func makeCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        if let cachedInput, let cachedCSS,
           cachedInput.theme == theme,
           cachedInput.syntaxTheme == syntaxTheme,
           cachedInput.baseFontSize == baseFontSize {
            return cachedCSS
        }

        let css = generateCSS(theme: theme, syntaxTheme: syntaxTheme, baseFontSize: baseFontSize)
        cachedInput = (theme, syntaxTheme, baseFontSize)
        cachedCSS = css
        return css
    }

    private static func generateCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
        let variables = theme.colors.cssVariables(baseFontSize: baseFontSize)
        // ... rest of the existing CSS string template unchanged
```

Move the entire CSS string template from the old `makeCSS` into the new `generateCSS` method. The public `makeCSS` signature and return type stay identical — `ReaderCSSFactory.makeCSS` continues to call it without changes.

- [ ] **Step 4: Run the cache tests and full rendering tests**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderCSSFactoryCacheTests -only-testing:minimarkTests/RenderingAndDiffTests -only-testing:minimarkTests/MarkdownRenderingServiceTests 2>&1 | tail -20
```

Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Support/ReaderCSSThemeGenerator.swift minimarkTests/Rendering/ReaderCSSFactoryTests.swift
git commit -m "perf: cache CSS generation for repeated appearance renders (#136)"
```

---

### Task 5: Full integration verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run:
```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30
```

Expected: ALL PASS

- [ ] **Step 2: Build the release configuration**

Run:
```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit any remaining fixes if needed**
