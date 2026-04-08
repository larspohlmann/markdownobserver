# Overlay Inset Alignment and Scroll Landing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make top overlays and scroll targets use one shared inset model so controls stay aligned and changed-region/TOC navigation lands below them across top bar, source-edit bar, and warning-bar states.

**Architecture:** Add a small pure inset calculator to centralize geometry rules, then wire `ContentView` to feed measured warning-bar height and computed inset values into both overlay padding and `MarkdownWebView`. Update the web runtime to accept host-provided inset updates and use them for changed-region targeting. Keep warning bars in the existing vertical flow under `ReaderTopBar`, while overlays move down together from the shared inset.

**Tech Stack:** SwiftUI, WebKit, JavaScript runtime embedded via `ReaderCSSFactory`, Swift Testing

**Spec:** `docs/superpowers/specs/2026-04-07-overlay-inset-alignment-design.md`

---

## File Structure

- `minimark/Support/ReaderOverlayInsetCalculator.swift` (create)
  - Pure geometry logic for top overlay paddings and scroll landing inset.
- `minimarkTests/Core/ReaderOverlayInsetCalculatorTests.swift` (create)
  - Unit tests for inset math across all requested UI states.
- `minimark/ContentView.swift` (modify)
  - Measure warning-bar height, compute shared inset values, apply to watch/prev-next/right-rail, pass scroll inset into web surface configuration.
- `minimark/Views/MarkdownWebView.swift` (modify)
  - Accept dynamic `overlayTopInset`, push updates to JS runtime, use same inset in TOC heading scroll script.
- `minimark/App/Resources/markdownobserver-runtime.js` (modify)
  - Replace static inset behavior with mutable host-updated inset for changed-region navigation math.
- `minimarkTests/Rendering/RenderingAndDiffTests.swift` (modify)
  - Regression tests that runtime HTML includes mutable overlay inset setter and change-nav math still uses the shared inset variable.

---

### Task 1: Add a pure overlay inset calculator with tests

**Files:**
- Create: `minimark/Support/ReaderOverlayInsetCalculator.swift`
- Create: `minimarkTests/Core/ReaderOverlayInsetCalculatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// minimarkTests/Core/ReaderOverlayInsetCalculatorTests.swift
import CoreGraphics
import Testing
@testable import minimark

@Suite
struct ReaderOverlayInsetCalculatorTests {
    @Test func computesInsetsForTopBarOnly() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            statusBannerHeight: 0
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 98)
    }

    @Test func computesInsetsWhenSourceEditBarAndWarningBarAreVisible() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 66,
            statusBannerHeight: 42
        )

        #expect(result.railTopPadding == 116)
        #expect(result.leadingOverlayTopPadding == 124)
        #expect(result.scrollTargetTopInset == 162)
    }

    @Test func clampsNegativeBannerHeightToZero() {
        let result = ReaderOverlayInsetCalculator.compute(
            topBarInset: 44,
            statusBannerHeight: -12
        )

        #expect(result.railTopPadding == 52)
        #expect(result.leadingOverlayTopPadding == 60)
        #expect(result.scrollTargetTopInset == 98)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:
`xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderOverlayInsetCalculatorTests`

Expected:
- Build/test failure because `ReaderOverlayInsetCalculator` does not exist yet.

- [ ] **Step 3: Implement minimal calculator**

```swift
// minimark/Support/ReaderOverlayInsetCalculator.swift
import CoreGraphics

struct ReaderOverlayInsetValues: Equatable {
    let railTopPadding: CGFloat
    let leadingOverlayTopPadding: CGFloat
    let scrollTargetTopInset: CGFloat
}

enum ReaderOverlayInsetCalculator {
    static let overlayBaseGap: CGFloat = 8
    static let leadingOverlayAlignmentAdjustment: CGFloat = 8
    static let overlayControlHeight: CGFloat = 30
    static let scrollLandingGap: CGFloat = 8

    static func compute(topBarInset: CGFloat, statusBannerHeight: CGFloat) -> ReaderOverlayInsetValues {
        let safeTopBarInset = max(0, topBarInset)
        let safeStatusBannerHeight = max(0, statusBannerHeight)
        let overlayBaseInset = safeTopBarInset + safeStatusBannerHeight + overlayBaseGap
        let railTopPadding = overlayBaseInset
        let leadingOverlayTopPadding = overlayBaseInset + leadingOverlayAlignmentAdjustment
        let scrollTargetTopInset = leadingOverlayTopPadding + overlayControlHeight + scrollLandingGap

        return ReaderOverlayInsetValues(
            railTopPadding: railTopPadding,
            leadingOverlayTopPadding: leadingOverlayTopPadding,
            scrollTargetTopInset: scrollTargetTopInset
        )
    }
}
```

- [ ] **Step 4: Re-run tests and confirm pass**

Run:
`xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderOverlayInsetCalculatorTests`

Expected:
- `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit Task 1**

```bash
git add minimark/Support/ReaderOverlayInsetCalculator.swift minimarkTests/Core/ReaderOverlayInsetCalculatorTests.swift
git commit -m "test: add overlay inset calculator coverage for issue 186"
```

---

### Task 2: Wire `ContentView` to measured warning height and shared inset values

**Files:**
- Modify: `minimark/ContentView.swift`

- [ ] **Step 1: Add warning-height state and surface configuration field**

```swift
// In ContentView state properties
@State private var statusBannerHeight: CGFloat = 0

// In DocumentSurfaceConfiguration
let overlayTopInset: CGFloat
```

- [ ] **Step 2: Add a reusable height-reporting preference key**

```swift
// Add near other private helper types in ContentView.swift
private struct TopStatusBannerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportTopStatusBannerHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TopStatusBannerHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        )
    }
}
```

- [ ] **Step 3: Measure warning bar height and reset when hidden**

```swift
// Replace warning-bar block in baseBody VStack
if readerStore.isCurrentFileMissing {
    DeletedFileWarningBar(
        fileName: readerStore.fileDisplayName,
        message: readerStore.lastError?.message
    )
    .reportTopStatusBannerHeight()
} else if readerStore.needsImageDirectoryAccess {
    ImageAccessWarningBar {
        promptForImageDirectoryAccess()
    }
    .reportTopStatusBannerHeight()
}

// Add onPreferenceChange on the VStack containing warning + surface
.onPreferenceChange(TopStatusBannerHeightPreferenceKey.self) { height in
    statusBannerHeight = max(0, height)
}
```

- [ ] **Step 4: Compute and apply shared inset values for all overlays**

```swift
// Add computed property in ContentView
private var overlayInsets: ReaderOverlayInsetValues {
    ReaderOverlayInsetCalculator.compute(
        topBarInset: overlayTopInset,
        statusBannerHeight: statusBannerHeight
    )
}

// Replace overlay paddings in documentSurfaceWithOverlays
.overlay(alignment: .topTrailing) {
    contentUtilityRail
        .padding(.top, overlayInsets.railTopPadding)
        .environment(\.colorScheme, overlayColorScheme ?? colorScheme)
}

.overlay(alignment: .topLeading) {
    if canNavigateChangedRegions {
        ChangeNavigationPill(
            currentIndex: currentChangedRegionIndex,
            totalCount: readerStore.changedRegions.count,
            onNavigate: requestChangedRegionNavigation
        )
        .padding(.top, overlayInsets.leadingOverlayTopPadding)
        .padding(.leading, 8)
        .environment(\.colorScheme, overlayColorScheme ?? colorScheme)
    }
}

.overlay(alignment: .top) {
    if let activeWatch = folderWatchState.activeFolderWatch {
        WatchPill(
            activeFolderWatch: activeWatch,
            isCurrentWatchAFavorite: folderWatchState.isCurrentWatchAFavorite,
            canStop: folderWatchState.canStopFolderWatch,
            onStop: callbacks.onStopFolderWatch,
            onSaveFavorite: callbacks.onSaveFolderWatchAsFavorite,
            onRemoveFavorite: callbacks.onRemoveCurrentWatchFromFavorites,
            onRevealInFinder: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeWatch.folderURL.path)
            },
            isAppearanceLocked: folderWatchState.isAppearanceLocked,
            onToggleAppearanceLock: callbacks.onToggleAppearanceLock
        )
        .padding(.top, overlayInsets.leadingOverlayTopPadding)
        .padding(.leading, canNavigateChangedRegions ? 150 : 60)
        .padding(.trailing, 70)
        .environment(\.colorScheme, overlayColorScheme ?? colorScheme)
    }
}
```

- [ ] **Step 5: Pass computed scroll inset into document surfaces**

```swift
// In both preview and source DocumentSurfaceConfiguration initializers
overlayTopInset: overlayInsets.scrollTargetTopInset,
```

- [ ] **Step 6: Build to validate integration compiles**

Run:
`xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected:
- `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit Task 2**

```bash
git add minimark/ContentView.swift
git commit -m "fix(reader): unify overlay top inset geometry in ContentView (#186)"
```

---

### Task 3: Add dynamic overlay inset bridge in `MarkdownWebView`

**Files:**
- Modify: `minimark/Views/MarkdownWebView.swift`

- [ ] **Step 1: Add a new input and pass-through field**

```swift
// In MarkdownWebView properties
var overlayTopInset: CGFloat = 56

// In ContentView.DocumentSurfaceHost MarkdownWebView initializer call
overlayTopInset: configuration.overlayTopInset,
```

- [ ] **Step 2: Push inset updates from update cycle into coordinator**

```swift
// In updateNSView(_:context:)
context.coordinator.overlayTopInset = max(0, overlayTopInset)
context.coordinator.updateOverlayTopInsetIfNeeded(in: webView)
```

- [ ] **Step 3: Add coordinator runtime update helper**

```swift
// In Coordinator properties
var overlayTopInset: CGFloat = 56
private var lastAppliedOverlayTopInset: CGFloat?

// In Coordinator methods
func updateOverlayTopInsetIfNeeded(in webView: WKWebView) {
    let inset = max(0, overlayTopInset)
    guard lastAppliedOverlayTopInset != inset else {
        return
    }

    lastAppliedOverlayTopInset = inset
    let insetLiteral = String(format: "%.3f", inset)
    let script = """
    (() => {
      if (typeof window.__minimarkSetOverlayTopInset === 'function') {
        return window.__minimarkSetOverlayTopInset(\(insetLiteral));
      }
      window.__minimarkOverlayTopInset = \(insetLiteral);
      return true;
    })();
    """

    webView.evaluateJavaScript(script)
}
```

- [ ] **Step 4: Ensure inset is re-applied after navigations complete**

```swift
// In webView(_:didFinish:)
updateOverlayTopInsetIfNeeded(in: webView)
```

- [ ] **Step 5: Use same inset for TOC heading scroll script**

```swift
private func scrollToHeadingElement(_ elementID: String, in webView: WKWebView) {
    let idLiteral = javaScriptStringLiteral(elementID)
    let insetLiteral = String(format: "%.3f", max(0, overlayTopInset))
    let script = """
    (() => {
      const el = document.getElementById(\(idLiteral));
      if (!el) return false;
      const inset = \(insetLiteral);
      const rect = el.getBoundingClientRect();
      const scrollTop = window.scrollY + rect.top - inset;
      window.scrollTo({ top: Math.max(0, scrollTop), behavior: 'smooth' });
      return true;
    })();
    """
    webView.evaluateJavaScript(script)
}
```

- [ ] **Step 6: Build to verify no WebView compile regressions**

Run:
`xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected:
- `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit Task 3**

```bash
git add minimark/Views/MarkdownWebView.swift minimark/ContentView.swift
git commit -m "fix(reader): pass dynamic overlay inset through MarkdownWebView (#186)"
```

---

### Task 4: Make runtime inset mutable and add regression tests

**Files:**
- Modify: `minimark/App/Resources/markdownobserver-runtime.js`
- Modify: `minimarkTests/Rendering/RenderingAndDiffTests.swift`

- [ ] **Step 1: Add failing regression tests for runtime HTML output**

```swift
// Add to minimarkTests/Rendering/RenderingAndDiffTests.swift
@Test func htmlRuntimeExposesOverlayTopInsetSetter() {
    let factory = ReaderCSSFactory()
    let html = factory.makeHTMLDocument(
        css: "",
        payloadBase64: "",
        runtimeAssets: ReaderRuntimeAssets(
            markdownItScriptPath: "markdown-it.min.js",
            highlightScriptPath: "highlight.min.js",
            taskListsScriptPath: nil,
            footnoteScriptPath: nil,
            attrsScriptPath: nil,
            deflistScriptPath: nil
        )
    )

    #expect(html.contains("function setOverlayTopInset(value)"))
    #expect(html.contains("window.__minimarkSetOverlayTopInset = function (value)"))
}

@Test func htmlRuntimeChangedRegionNavigationUsesMutableOverlayInsetVariable() {
    let factory = ReaderCSSFactory()
    let html = factory.makeHTMLDocument(
        css: "",
        payloadBase64: "",
        runtimeAssets: ReaderRuntimeAssets(
            markdownItScriptPath: "markdown-it.min.js",
            highlightScriptPath: "highlight.min.js",
            taskListsScriptPath: nil,
            footnoteScriptPath: nil,
            attrsScriptPath: nil,
            deflistScriptPath: nil
        )
    )

    #expect(html.contains("overlayTopInset = Math.max(0, numericValue);"))
    #expect(html.contains("row.top - overlayTopInset"))
    #expect(html.contains("var probeTop = currentTop + overlayTopInset;"))
}
```

- [ ] **Step 2: Run targeted tests and confirm failure**

Run:
`xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/RenderingAndDiffTests`

Expected:
- Failing assertions because setter function is not present yet.

- [ ] **Step 3: Implement mutable inset setter in runtime JS**

```javascript
// In minimark/App/Resources/markdownobserver-runtime.js
var overlayTopInset = 56;

function setOverlayTopInset(value) {
  var numericValue = Number(value);
  if (!Number.isFinite(numericValue)) {
    return false;
  }

  overlayTopInset = Math.max(0, numericValue);
  window.__minimarkOverlayTopInset = overlayTopInset;
  return true;
}

window.__minimarkSetOverlayTopInset = function (value) {
  return setOverlayTopInset(value);
};

// Keep legacy global for compatibility on initial load.
window.__minimarkOverlayTopInset = overlayTopInset;
```

- [ ] **Step 4: Re-run targeted tests and confirm pass**

Run:
`xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/RenderingAndDiffTests`

Expected:
- `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit Task 4**

```bash
git add minimark/App/Resources/markdownobserver-runtime.js minimarkTests/Rendering/RenderingAndDiffTests.swift
git commit -m "fix(runtime): support host-updated overlay inset for navigation targets (#186)"
```

---

### Task 5: Verify behavior matrix and run full test suite

**Files:**
- Modify: none (verification-only task)

- [ ] **Step 1: Build debug app**

Run:
`xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`

Expected:
- `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run full unit suite**

Run:
`xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`

Expected:
- `** TEST SUCCEEDED **`

- [ ] **Step 3: Manual UI verification for required states**

Use the app and validate all of the following:

1. Top bar only: watch/prev-next top borders align with right rail top border.
2. Source edit bar visible: all three overlays move down together and do not overlap edit bar.
3. Deleted warning visible: warning bar is directly below top bar; overlays move below warning.
4. Image-access warning visible: same behavior as deleted warning.
5. Changed-region navigation lands below watch/prev-next with consistent margin.
6. TOC heading navigation lands below watch/prev-next with consistent margin.

- [ ] **Step 4: Commit final verification note (if any small tweaks were needed)**

```bash
git add -A
git commit -m "fix(reader): finalize overlay alignment and navigation landing behavior (#186)"
```

---

## Self-Review Checklist

- Spec coverage: all five acceptance criteria map to Tasks 2–5.
- Placeholder scan: no TODO/TBD placeholders remain.
- Type consistency: `overlayTopInset` naming is consistent across `ContentView`, `DocumentSurfaceConfiguration`, `MarkdownWebView`, and runtime JS.
