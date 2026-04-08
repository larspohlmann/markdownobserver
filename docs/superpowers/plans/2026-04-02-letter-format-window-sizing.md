# Letter-Format Window Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Default window gives the content area a US Letter aspect ratio, and the window widens/narrows when the sidebar appears/hides to preserve that ratio.

**Architecture:** Replace the golden ratio constant in `ReaderWindowDefaults` with US Letter ratio (11/8.5). Add a sidebar-aware resize helper that adjusts the `NSWindow` width when sidebar document count crosses the 1-document threshold. The resize clamps to the current screen bounds and uses animated frame changes.

**Tech Stack:** Swift, AppKit (NSWindow), SwiftUI

---

### Task 1: Change aspect ratio from golden ratio to US Letter

**Files:**
- Modify: `minimark/Support/ReaderWindowDefaults.swift`
- Modify: `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`

- [ ] **Step 1: Update the failing tests to expect letter ratio**

In `minimarkTests/Core/ReaderSettingsAndModelsTests.swift`, update the four `ReaderWindowDefaults` tests. Replace `goldenRatio` with `letterAspectRatio`:

```swift
@Test func readerWindowDefaultsUseBaseSizeWhenVisibleFrameCanFitIt() {
    let size = ReaderWindowDefaults.size(forVisibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 2200))

    #expect(size.width == ReaderWindowDefaults.baseWidth)
    #expect(size.height == ReaderWindowDefaults.baseHeight)
}

@Test func readerWindowDefaultsClampToVisibleHeightWhilePreservingAspectRatio() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = ReaderWindowDefaults.size(forVisibleFrame: visibleFrame)
    let expectedHeight = visibleFrame.height * ReaderWindowDefaults.fittedHeightUsage
    let expectedWidth = expectedHeight / ReaderWindowDefaults.letterAspectRatio

    #expect(size.width == expectedWidth)
    #expect(size.height == expectedHeight)
}

@Test func readerWindowDefaultsKeepMinimumUsableWidthWhenScreenIsCloseToFittingIt() {
    let minimumUsableHeight = ReaderWindowDefaults.minimumUsableWidth * ReaderWindowDefaults.letterAspectRatio
    let visibleFrame = CGRect(
        x: 0,
        y: 0,
        width: 1440,
        height: minimumUsableHeight * ReaderWindowDefaults.minimumUsableHeightTolerance
    )

    let size = ReaderWindowDefaults.size(forVisibleFrame: visibleFrame)

    #expect(size.width == ReaderWindowDefaults.minimumUsableWidth)
    #expect(size.height == minimumUsableHeight)
}

@Test func readerWindowDefaultsPreferFittedSizeWhenMinimumUsableWidthWouldStillBeTooTall() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 1280, height: 820)
    let size = ReaderWindowDefaults.size(forVisibleFrame: visibleFrame)

    #expect(size.width < ReaderWindowDefaults.minimumUsableWidth)
    #expect(size.height == visibleFrame.height * ReaderWindowDefaults.fittedHeightUsage)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests`
Expected: Tests fail because `letterAspectRatio` does not exist yet and `goldenRatio` still does.

- [ ] **Step 3: Implement the ratio change in ReaderWindowDefaults**

In `minimark/Support/ReaderWindowDefaults.swift`, replace the full file contents:

```swift
import AppKit
import CoreGraphics

enum ReaderWindowDefaults {
    static let letterAspectRatio: CGFloat = 11.0 / 8.5
    static let baseWidth: CGFloat = 1100
    static let baseHeight: CGFloat = baseWidth * letterAspectRatio
    static let minimumUsableWidth: CGFloat = 640
    static let fittedHeightUsage: CGFloat = 0.9
    static let minimumUsableHeightTolerance: CGFloat = 0.96

    static var defaultWidth: CGFloat {
        defaultSize.width
    }

    static var defaultHeight: CGFloat {
        defaultSize.height
    }

    static var defaultSize: CGSize {
        guard let visibleFrame = preferredVisibleFrame else {
            return CGSize(width: baseWidth, height: baseHeight)
        }

        return size(forVisibleFrame: visibleFrame)
    }

    static func size(forVisibleFrame visibleFrame: CGRect) -> CGSize {
        let fittedSize = fittedSize(maxWidth: visibleFrame.width, maxHeight: visibleFrame.height * fittedHeightUsage)
        let minimumUsableHeight = minimumUsableWidth * letterAspectRatio

        guard fittedSize.width < minimumUsableWidth,
              visibleFrame.width >= minimumUsableWidth,
              visibleFrame.height >= minimumUsableHeight * minimumUsableHeightTolerance else {
            return fittedSize
        }

        return CGSize(width: minimumUsableWidth, height: minimumUsableHeight)
    }

    private static var preferredVisibleFrame: CGRect? {
        if let mainScreen = NSScreen.main {
            return mainScreen.visibleFrame
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen.visibleFrame
        }

        return NSScreen.screens.first?.visibleFrame
    }

    private static func fittedSize(maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
        let scale = min(1, maxWidth / baseWidth, maxHeight / baseHeight)
        return CGSize(
            width: max(baseWidth * scale, 1),
            height: max(baseHeight * scale, 1)
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSettingsAndModelsTests`
Expected: All four `ReaderWindowDefaults` tests pass.

- [ ] **Step 5: Commit**

```bash
git add minimark/Support/ReaderWindowDefaults.swift minimarkTests/Core/ReaderSettingsAndModelsTests.swift
git commit -m "feat(#62): change default window aspect ratio from golden ratio to US Letter"
```

---

### Task 2: Add sidebar-aware window resize logic

**Files:**
- Modify: `minimark/Support/ReaderWindowDefaults.swift` (add resize helper)
- Create: `minimarkTests/Core/ReaderWindowResizeTests.swift` (test the delta calculation)

- [ ] **Step 1: Write tests for the sidebar resize frame calculation**

Create `minimarkTests/Core/ReaderWindowResizeTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import minimark

struct ReaderWindowResizeTests {
    @Test func sidebarShownWidensWindowByRequestedAmount() {
        let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        #expect(result.width == 1050)
        #expect(result.height == 1000)
        #expect(result.origin.x == 100)
        #expect(result.origin.y == 100)
    }

    @Test func sidebarHiddenNarrowsWindowByRequestedAmount() {
        let windowFrame = CGRect(x: 100, y: 100, width: 1050, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: -250
        )

        #expect(result.width == 800)
        #expect(result.height == 1000)
        #expect(result.origin.x == 100)
    }

    @Test func sidebarShownClampsToScreenWidthWhenNoRoomRight() {
        let windowFrame = CGRect(x: 1700, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        // Window should shift left to fit
        #expect(result.width == 1050)
        #expect(result.maxX <= screenFrame.maxX)
        #expect(result.origin.x >= screenFrame.origin.x)
    }

    @Test func sidebarShownClampsWidthWhenDeltaExceedsScreen() {
        let windowFrame = CGRect(x: 0, y: 100, width: 800, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 900, height: 1080)

        let result = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: 250
        )

        // Cannot exceed screen width
        #expect(result.width == 900)
        #expect(result.origin.x == 0)
    }

    @Test func sidebarHiddenDoesNotNarrowBelowMinimumUsableWidth() {
        let windowFrame = CGRect(x: 100, y: 100, width: 700, height: 1000)
        let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = ReaderWindowDefaults.sidebarResizedFrame(
            windowFrame: windowFrame,
            screenVisibleFrame: screenFrame,
            sidebarDelta: -250
        )

        #expect(result.width >= ReaderWindowDefaults.minimumUsableWidth)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderWindowResizeTests`
Expected: Fails because `sidebarResizedFrame` does not exist.

- [ ] **Step 3: Implement the resize helper**

Add to the bottom of `minimark/Support/ReaderWindowDefaults.swift` (inside the `enum`), before the closing `}`:

```swift
    static func sidebarResizedFrame(
        windowFrame: CGRect,
        screenVisibleFrame: CGRect,
        sidebarDelta: CGFloat
    ) -> CGRect {
        let targetWidth = max(windowFrame.width + sidebarDelta, minimumUsableWidth)
        let clampedWidth = min(targetWidth, screenVisibleFrame.width)

        var newOriginX = windowFrame.origin.x

        // If expanding rightward would go off-screen, shift left
        if newOriginX + clampedWidth > screenVisibleFrame.maxX {
            newOriginX = screenVisibleFrame.maxX - clampedWidth
        }

        // Don't go past the left edge
        newOriginX = max(newOriginX, screenVisibleFrame.origin.x)

        return CGRect(
            x: newOriginX,
            y: windowFrame.origin.y,
            width: clampedWidth,
            height: windowFrame.height
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderWindowResizeTests`
Expected: All five tests pass.

- [ ] **Step 5: Commit**

```bash
git add minimark/Support/ReaderWindowDefaults.swift minimarkTests/Core/ReaderWindowResizeTests.swift
git commit -m "feat(#62): add sidebar-aware window resize frame calculation"
```

---

### Task 3: Wire sidebar visibility changes to window resize

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift` (add onChange for document count)

- [ ] **Step 1: Add an onChange handler for sidebar visibility in ReaderWindowRootView**

In `minimark/Views/ReaderWindowRootView.swift`, inside the `windowLifecycleAwareView` function, add a new `.onChange` modifier after the existing `.onChange(of: sidebarDocumentController.selectedDocumentID)` block (around line 188). Track the document count crossing the sidebar threshold (1 → 2+ means sidebar appeared, 2+ → 1 means sidebar hidden):

Add a new `@State` property after the existing `@State var sidebarWidth` (line 27):

```swift
@State private var wasSidebarVisible = false
```

Then add this `.onChange` inside `windowLifecycleAwareView`, after the `.onChange(of: sidebarDocumentController.selectedDocumentID)` block:

```swift
.onChange(of: sidebarDocumentController.documents.count) { oldCount, newCount in
    let isSidebarVisible = newCount > 1
    let wasVisible = oldCount > 1

    guard isSidebarVisible != wasVisible, let window = hostWindow else {
        return
    }

    let delta = isSidebarVisible
        ? sidebarWidth
        : -sidebarWidth

    guard let screenFrame = window.screen?.visibleFrame else {
        return
    }

    let newFrame = ReaderWindowDefaults.sidebarResizedFrame(
        windowFrame: window.frame,
        screenVisibleFrame: screenFrame,
        sidebarDelta: delta
    )

    window.setFrame(newFrame, display: true, animate: true)
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`
Expected: Build succeeds.

- [ ] **Step 3: Run full test suite to check for regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/ReaderWindowRootView.swift
git commit -m "feat(#62): widen/narrow window when sidebar appears/hides"
```

---

### Task 4: Clean up unused state and verify

- [ ] **Step 1: Remove the `wasSidebarVisible` state if it was added but unused**

Check if the `@State private var wasSidebarVisible = false` property added in Task 3 is actually used. The `.onChange(of:)` with old/new count parameters makes it unnecessary. If it was added, remove it.

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`
Expected: All tests pass.

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore(#62): clean up unused state"
```
