# Table of Contents Overlay — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a TOC button to the utility rail that opens a popover listing h1–h3 headings, with click-to-scroll navigation and a `Cmd+Shift+T` keyboard shortcut.

**Architecture:** JavaScript extracts headings from the rendered DOM (preview/split) or raw markdown (source mode) and posts them to Swift via a `minimarkTOC` message handler. Swift stores headings on `ReaderStore` and drives a popover UI in `ContentUtilityRail`. Scroll-to-heading reuses the existing `scrollToFragment` pattern for preview/split and line-based textarea scrolling for source mode.

**Tech Stack:** SwiftUI, WebKit (WKScriptMessageHandler), JavaScript, Swift Testing

**Spec:** `docs/superpowers/specs/2026-04-06-table-of-contents-overlay-design.md`

---

### Task 1: Create TOCHeading model

**Files:**
- Create: `minimark/Models/TOCHeading.swift`
- Test: `minimarkTests/Core/TOCHeadingTests.swift`

- [ ] **Step 1: Write the test for TOCHeading**

```swift
// minimarkTests/Core/TOCHeadingTests.swift
import Foundation
import Testing
@testable import minimark

@Suite
struct TOCHeadingTests {
    @Test func initializesWithAllProperties() {
        let heading = TOCHeading(elementID: "introduction", level: 1, title: "Introduction", sourceLine: 3)
        #expect(heading.elementID == "introduction")
        #expect(heading.level == 1)
        #expect(heading.title == "Introduction")
        #expect(heading.sourceLine == 3)
    }

    @Test func sourceLineCanBeNil() {
        let heading = TOCHeading(elementID: "setup", level: 2, title: "Setup", sourceLine: nil)
        #expect(heading.sourceLine == nil)
    }

    @Test func equatableComparesAllFields() {
        let a = TOCHeading(elementID: "a", level: 1, title: "A", sourceLine: 1)
        let b = TOCHeading(elementID: "a", level: 1, title: "A", sourceLine: 1)
        let c = TOCHeading(elementID: "a", level: 2, title: "A", sourceLine: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func identifiableUsesCompoundID() {
        let h1 = TOCHeading(elementID: "intro", level: 1, title: "Intro", sourceLine: 1)
        let h2 = TOCHeading(elementID: "intro", level: 1, title: "Intro", sourceLine: 5)
        #expect(h1.id != h2.id)
    }

    @Test func parsesFromJavaScriptPayload() {
        let payload: [[String: Any]] = [
            ["id": "getting-started", "level": 2, "title": "Getting Started", "sourceLine": 10],
            ["id": "installation", "level": 3, "title": "Installation", "sourceLine": 15],
            ["id": "", "level": 1, "title": "Source Only", "sourceLine": 1]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 3)
        #expect(headings[0].elementID == "getting-started")
        #expect(headings[0].level == 2)
        #expect(headings[0].title == "Getting Started")
        #expect(headings[0].sourceLine == 10)
        #expect(headings[2].elementID == "")
        #expect(headings[2].sourceLine == 1)
    }

    @Test func parsesFromJavaScriptPayloadSkipsInvalidEntries() {
        let payload: [[String: Any]] = [
            ["id": "ok", "level": 1, "title": "OK", "sourceLine": 1],
            ["level": 2, "title": "Missing ID"],
            ["id": "ok2", "level": 1, "title": "OK2", "sourceLine": 3]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 2)
        #expect(headings[0].title == "OK")
        #expect(headings[1].title == "OK2")
    }

    @Test func parsesNullSourceLineAsNil() {
        let payload: [[String: Any]] = [
            ["id": "test", "level": 1, "title": "Test", "sourceLine": NSNull()]
        ]
        let headings = TOCHeading.fromJavaScriptPayload(payload)
        #expect(headings.count == 1)
        #expect(headings[0].sourceLine == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/TOCHeadingTests 2>&1 | tail -20`
Expected: FAIL — `TOCHeading` type not found

- [ ] **Step 3: Write minimal implementation**

The stored property is named `elementID` (not `id`) to avoid colliding with `Identifiable.id`. The `Identifiable.id` is a computed compound key for stable SwiftUI identity.

```swift
// minimark/Models/TOCHeading.swift
import Foundation

struct TOCHeading: Equatable, Sendable {
    let elementID: String
    let level: Int
    let title: String
    let sourceLine: Int?

    static func fromJavaScriptPayload(_ payload: [[String: Any]]) -> [TOCHeading] {
        payload.compactMap { entry in
            guard let elementID = entry["id"] as? String,
                  let level = entry["level"] as? Int,
                  let title = entry["title"] as? String else {
                return nil
            }
            let sourceLine = entry["sourceLine"] as? Int
            return TOCHeading(elementID: elementID, level: level, title: title, sourceLine: sourceLine)
        }
    }
}

extension TOCHeading: Identifiable {
    var id: String {
        "\(elementID)-\(level)-\(sourceLine ?? 0)"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/TOCHeadingTests 2>&1 | tail -20`
Expected: PASS — all 6 tests green

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/TOCHeading.swift minimarkTests/Core/TOCHeadingTests.swift
git commit -m "feat(toc): add TOCHeading model with JS payload parsing (#158)"
```

---

### Task 2: Add JavaScript heading extraction to runtime

**Files:**
- Modify: `minimark/App/Resources/markdownobserver-runtime.js`

The `extractHeadings()` function must be called after every render and exposed as a global so Swift can trigger re-extraction.

- [ ] **Step 1: Add `extractHeadings` function and call it after render**

In `markdownobserver-runtime.js`, add the function before the `renderMarkdown` function (around line 1638), and call it at the end of the `renderMarkdown` function's `typesetMath` callback:

```javascript
// Add before renderMarkdown (around line 1638):
  function extractHeadings() {
    try {
      var headings = document.querySelectorAll("h1, h2, h3");
      var result = [];
      for (var i = 0; i < headings.length; i += 1) {
        var el = headings[i];
        result.push({
          id: el.id || "",
          level: parseInt(el.tagName.charAt(1), 10),
          title: (el.textContent || "").trim(),
          sourceLine: parseInt(el.getAttribute("data-src-line-start"), 10) || null
        });
      }
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.minimarkTOC) {
        window.webkit.messageHandlers.minimarkTOC.postMessage(result);
      }
    } catch (_) {}
  }
```

In the `renderMarkdown` function, add `extractHeadings();` at the end of the `typesetMath` callback, after `applyScrollProgress`:

```javascript
    typesetMath(root, function () {
      renderUnsavedDraftHighlights(root, payload.unsavedChangedRegions || []);
      renderChangedRegionGutter(root, gutter, payload.changedRegions || []);
      applyScrollProgress(scrollAnchorProgress);

      // Auto-expand the first edited gutter pill (screenshot automation)
      var autoExpandMeta = document.querySelector('meta[name="minimark-auto-expand-first-edit"]');
      if (autoExpandMeta && autoExpandMeta.getAttribute("content") === "true") {
        var editedButton = gutter.querySelector(".reader-gutter-row-edited");
        if (editedButton) {
          editedButton.click();
          autoExpandMeta.setAttribute("content", "done");
        }
      }

      extractHeadings();
    });
```

Also expose it as a global for re-extraction:

```javascript
  window.__minimarkExtractHeadings = function () {
    extractHeadings();
    return true;
  };
```

Add this next to the existing `window.__minimarkUpdateRenderedMarkdown` global (around line 1674).

- [ ] **Step 2: Build to verify no JS syntax errors**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/App/Resources/markdownobserver-runtime.js
git commit -m "feat(toc): add heading extraction to markdown runtime (#158)"
```

---

### Task 3: Add source-mode heading extraction to source HTML renderer

**Files:**
- Modify: `minimark/Support/MarkdownSourceHTMLRenderer.swift`

In source mode there's no rendered DOM, so we scan the raw markdown text for ATX headings (h1–h3), skipping code fences. The extraction runs on page load and after each input event.

- [ ] **Step 1: Add the extraction script to the source HTML bootstrap**

In `MarkdownSourceHTMLRenderer.swift`, in the `isEditable` branch of `makeHTMLDocument` (around line 41), add a heading extraction function to the bootstrap script. Insert it after `window.__minimarkSourceBootstrapStatus = "ready";` (line 98) and before the `requestAnimationFrame` call:

```swift
// In the isEditable bootstrap script, after root.replaceChildren(textarea):
                    function extractSourceHeadings(text) {
                        try {
                            var lines = text.split("\\n");
                            var result = [];
                            var inCodeFence = false;
                            for (var i = 0; i < lines.length; i++) {
                                if (/^```|^~~~/.test(lines[i])) { inCodeFence = !inCodeFence; continue; }
                                if (inCodeFence) continue;
                                var match = lines[i].match(/^(#{1,3})\\s+(.+)/);
                                if (match) {
                                    result.push({
                                        id: "",
                                        level: match[1].length,
                                        title: match[2].replace(/\\s+$/, ""),
                                        sourceLine: i + 1
                                    });
                                }
                            }
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.minimarkTOC) {
                                window.webkit.messageHandlers.minimarkTOC.postMessage(result);
                            }
                        } catch (_) {}
                    }

                    extractSourceHeadings(payload.markdown || "");

                    textarea.addEventListener("input", function() {
                        extractSourceHeadings(textarea.value);
                    });
```

Note: The existing `textarea.addEventListener("input", ...)` for `minimarkSourceEdit` is already there. Add the heading extraction as an additional listener **above** the existing one, or combine them. Adding a second listener is cleaner — keeps concerns separated.

The full modification: insert the `extractSourceHeadings` function definition and initial call right after `root.replaceChildren(textarea);` on line 97, and add the second input listener right after.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Support/MarkdownSourceHTMLRenderer.swift
git commit -m "feat(toc): add heading extraction to source editing mode (#158)"
```

---

### Task 4: Add minimarkTOC message handler to MarkdownWebView

**Files:**
- Modify: `minimark/Views/MarkdownWebView.swift`

Wire up the `minimarkTOC` message handler so heading data flows from JavaScript to Swift.

- [ ] **Step 1: Add the message name constant**

In `MarkdownWebView.swift`, add after line 9 (`sourceEditorDiagnosticMessageName`):

```swift
    private static let tocMessageName = "minimarkTOC"
```

- [ ] **Step 2: Register the message handler in makeNSView**

In `makeNSView`, after the existing `configuration.userContentController.add(...)` calls (after line 47):

```swift
        configuration.userContentController.add(context.coordinator, name: Self.tocMessageName)
```

- [ ] **Step 3: Add the callback property to Coordinator**

In the `Coordinator` class, after the existing `onSourceEdit` callback (line 133):

```swift
        var onTOCHeadingsExtracted: ([TOCHeading]) -> Void = { _ in }
```

- [ ] **Step 4: Wire the callback in updateNSView**

In `updateNSView`, add after the `context.coordinator.onSourceEdit = onSourceEdit` line (line 76):

```swift
        context.coordinator.onTOCHeadingsExtracted = onTOCHeadingsExtracted
```

This requires adding `onTOCHeadingsExtracted` as a property on `MarkdownWebView` itself:

```swift
    var onTOCHeadingsExtracted: ([TOCHeading]) -> Void = { _ in }
```

Add this after the existing `onSourceEdit` property (line 26).

- [ ] **Step 5: Handle the message in userContentController**

In `userContentController(_:didReceive:)` (line 571), add a new handler block before the final `guard message.name == MarkdownWebView.scrollSyncMessageName` check:

```swift
            if message.name == MarkdownWebView.tocMessageName,
               let payload = message.body as? [[String: Any]] {
                let headings = TOCHeading.fromJavaScriptPayload(payload)
                onTOCHeadingsExtracted(headings)
                return
            }
```

- [ ] **Step 6: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add minimark/Views/MarkdownWebView.swift
git commit -m "feat(toc): add minimarkTOC message handler to WebView (#158)"
```

---

### Task 5: Add TOC state to ReaderStore

**Files:**
- Create: `minimark/Stores/Coordination/ReaderStore+TableOfContents.swift`

- [ ] **Step 1: Add TOC properties to ReaderStore**

First, add the stored properties to `ReaderStore.swift` (around line 41, after the other forwarding computed properties):

```swift
    // MARK: - Table of Contents
    var tocHeadings: [TOCHeading] = []
    var isTOCVisible: Bool = false
```

- [ ] **Step 2: Create the coordination extension**

```swift
// minimark/Stores/Coordination/ReaderStore+TableOfContents.swift
import Foundation

extension ReaderStore {
    func updateTOCHeadings(_ headings: [TOCHeading]) {
        guard tocHeadings != headings else { return }
        tocHeadings = headings
    }

    func toggleTOC() {
        guard !tocHeadings.isEmpty else { return }
        isTOCVisible.toggle()
    }

    func hideTOC() {
        isTOCVisible = false
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add minimark/Stores/ReaderStore.swift minimark/Stores/Coordination/ReaderStore+TableOfContents.swift
git commit -m "feat(toc): add TOC state and coordination to ReaderStore (#158)"
```

---

### Task 6: Wire heading extraction callback from WebView to ReaderStore

**Files:**
- Modify: `minimark/ContentView.swift` (wherever `MarkdownWebView` is instantiated)

- [ ] **Step 1: Find and update MarkdownWebView usage**

Search for where `MarkdownWebView(` is instantiated in ContentView.swift and add the `onTOCHeadingsExtracted` callback. The callback should call `readerStore.updateTOCHeadings(headings)`.

Find the `MarkdownWebView(` call and add:

```swift
                    .onTOCHeadingsExtracted { headings in
                        readerStore.updateTOCHeadings(headings)
                    }
```

Note: If `MarkdownWebView` uses direct property assignment (not view modifiers), add the parameter directly to the initializer call:

```swift
    onTOCHeadingsExtracted: { headings in
        readerStore.updateTOCHeadings(headings)
    }
```

Check how `onSourceEdit` is wired in the same file and follow the same pattern.

- [ ] **Step 2: Clear headings on document change**

In `ReaderStore+DocumentOpenFlow.swift` or wherever the document identity changes, add `tocHeadings = []` to reset stale headings when switching documents. Find where `document = ReaderDocumentState.empty` or similar reset code lives and add the clearing there.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add minimark/ContentView.swift minimark/Stores/Coordination/ReaderStore+DocumentOpenFlow.swift
git commit -m "feat(toc): wire heading extraction from WebView to ReaderStore (#158)"
```

---

### Task 7: Create TOCPopoverView

**Files:**
- Create: `minimark/Views/Content/TOCPopoverView.swift`

- [ ] **Step 1: Create the popover view**

```swift
// minimark/Views/Content/TOCPopoverView.swift
import SwiftUI

struct TOCPopoverView: View {
    let headings: [TOCHeading]
    let onSelect: (TOCHeading) -> Void

    private enum Metrics {
        static let popoverMinWidth: CGFloat = 200
        static let popoverIdealWidth: CGFloat = 260
        static let popoverMaxWidth: CGFloat = 320
        static let popoverMaxHeight: CGFloat = 400
        static let rowHorizontalPadding: CGFloat = 12
        static let rowVerticalPadding: CGFloat = 5
        static let indentPerLevel: CGFloat = 16
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(headings) { heading in
                    Button {
                        onSelect(heading)
                    } label: {
                        Text(heading.title)
                            .font(headingFont(for: heading.level))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(heading.level - 1) * Metrics.indentPerLevel)
                            .padding(.horizontal, Metrics.rowHorizontalPadding)
                            .padding(.vertical, Metrics.rowVerticalPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(PointingHandCursor())
                }
            }
            .padding(.vertical, 8)
        }
        .frame(
            minWidth: Metrics.popoverMinWidth,
            idealWidth: Metrics.popoverIdealWidth,
            maxWidth: Metrics.popoverMaxWidth,
            maxHeight: Metrics.popoverMaxHeight
        )
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 13, weight: .semibold)
        default:
            return .system(size: 12)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/Content/TOCPopoverView.swift
git commit -m "feat(toc): add TOCPopoverView (#158)"
```

---

### Task 8: Add TOC button to ContentUtilityRail

**Files:**
- Modify: `minimark/Views/Content/ContentUtilityRail.swift`
- Modify: `minimark/ContentView.swift` (pass new properties to ContentUtilityRail)

- [ ] **Step 1: Add TOC properties to ContentUtilityRail**

Add new properties after `onStartSourceEditing`:

```swift
    let tocHeadings: [TOCHeading]
    let isTOCVisible: Binding<Bool>
    let onSelectTOCHeading: (TOCHeading) -> Void
```

- [ ] **Step 2: Add the TOC button group to the body**

In the `body`, add the TOC group after the edit group (before the closing of the outer VStack):

```swift
                if !tocHeadings.isEmpty {
                    groupSeparator
                    tocGroup
                }
```

- [ ] **Step 3: Add the tocGroup computed property**

Add after `editGroup`:

```swift
    // MARK: - TOC Group

    private var tocGroup: some View {
        Button {
            isTOCVisible.wrappedValue.toggle()
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: Metrics.iconSize, weight: isTOCVisible.wrappedValue ? .bold : .semibold))
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .railButtonBackground(cornerRadius: Metrics.buttonCornerRadius,
                    fill: isTOCVisible.wrappedValue ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06),
                    border: isTOCVisible.wrappedValue ? Color.primary.opacity(0.18) : Color.primary.opacity(0.10)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isTOCVisible.wrappedValue ? .primary : .secondary)
        .help("Table of Contents")
        .accessibilityLabel("Table of Contents")
        .accessibilityValue(isTOCVisible.wrappedValue ? "Visible" : "Hidden")
        .popover(isPresented: isTOCVisible, arrowEdge: .trailing) {
            TOCPopoverView(
                headings: tocHeadings,
                onSelect: { heading in
                    onSelectTOCHeading(heading)
                    isTOCVisible.wrappedValue = false
                }
            )
        }
    }
```

- [ ] **Step 4: Update ContentUtilityRail usage in ContentView.swift**

Find the `contentUtilityRail` computed property (line 550) and add the new parameters:

```swift
    private var contentUtilityRail: some View {
        ContentUtilityRail(
            hasFile: readerStore.fileURL != nil,
            documentViewMode: readerStore.documentViewMode,
            showEditButton: showSourceEditingControls && !readerStore.isSourceEditing,
            canStartSourceEditing: readerStore.canStartSourceEditing,
            onSetDocumentViewMode: { mode in
                readerStore.setDocumentViewMode(mode)
            },
            onStartSourceEditing: {
                readerStore.startEditingSource()
            },
            tocHeadings: readerStore.tocHeadings,
            isTOCVisible: Binding(
                get: { readerStore.isTOCVisible },
                set: { readerStore.isTOCVisible = $0 }
            ),
            onSelectTOCHeading: { heading in
                handleTOCHeadingSelection(heading)
            }
        )
    }
```

Add the `handleTOCHeadingSelection` method (placeholder for now — scroll dispatch comes in Task 9):

```swift
    private func handleTOCHeadingSelection(_ heading: TOCHeading) {
        // Scroll dispatch will be implemented in Task 9
    }
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add minimark/Views/Content/ContentUtilityRail.swift minimark/ContentView.swift
git commit -m "feat(toc): add TOC button to utility rail with popover (#158)"
```

---

### Task 9: Implement scroll-to-heading dispatch

**Files:**
- Modify: `minimark/ContentView.swift`

- [ ] **Step 1: Implement handleTOCHeadingSelection**

Replace the placeholder `handleTOCHeadingSelection` with the real implementation. The approach depends on how the WebView is accessed for JS evaluation. Find how `scrollToFragment` is triggered — it's called from inside `MarkdownWebView.Coordinator` via link navigation. For TOC, we need to trigger it externally.

The simplest approach: add a `tocScrollRequest` property to `MarkdownWebView` that triggers JS evaluation when set.

In `MarkdownWebView.swift`, add a new request type and property:

```swift
    var tocScrollRequest: TOCScrollRequest?
```

Add a simple request struct in `TOCHeading.swift` or a new file:

```swift
// Add to minimark/Models/TOCHeading.swift
struct TOCScrollRequest: Equatable {
    let heading: TOCHeading
    let requestID: Int
}
```

In `MarkdownWebView.Coordinator`, add a handler method:

```swift
        private var lastTOCScrollRequestID: Int?

        func handleTOCScrollRequestIfNeeded(_ request: TOCScrollRequest?, in webView: WKWebView) {
            guard let request, request.requestID != lastTOCScrollRequestID else { return }
            lastTOCScrollRequestID = request.requestID

            if !request.heading.elementID.isEmpty {
                scrollToFragment(request.heading.elementID, in: webView)
            } else if let sourceLine = request.heading.sourceLine {
                scrollToSourceLine(sourceLine, in: webView)
            }
        }

        private func scrollToSourceLine(_ line: Int, in webView: WKWebView) {
            let script = """
            (() => {
              const textarea = document.querySelector('.minimark-source-editor');
              if (!textarea) return false;
              const lines = textarea.value.substring(0, textarea.value.length).split('\\n');
              let charIndex = 0;
              for (let i = 0; i < Math.min(\(line) - 1, lines.length); i++) {
                charIndex += lines[i].length + 1;
              }
              textarea.focus();
              textarea.setSelectionRange(charIndex, charIndex);
              // Scroll the textarea so the line is visible
              const lineHeight = parseFloat(getComputedStyle(textarea).lineHeight) || 20;
              textarea.scrollTop = Math.max(0, (\(line) - 3) * lineHeight);
              return true;
            })();
            """
            webView.evaluateJavaScript(script)
        }
```

In `updateNSView`, add after other request handlers:

```swift
        context.coordinator.handleTOCScrollRequestIfNeeded(tocScrollRequest, in: webView)
```

- [ ] **Step 2: Add scroll request state to ReaderStore**

In `ReaderStore.swift`, add:

```swift
    var tocScrollRequest: TOCScrollRequest?
    private var tocScrollRequestCounter = 0
```

In `ReaderStore+TableOfContents.swift`, add:

```swift
    func scrollToTOCHeading(_ heading: TOCHeading) {
        tocScrollRequestCounter += 1
        tocScrollRequest = TOCScrollRequest(heading: heading, requestID: tocScrollRequestCounter)
        isTOCVisible = false
    }
```

Note: `tocScrollRequestCounter` needs to be accessible from the extension. Since it's in `ReaderStore.swift`, make it `internal` (not `private`). Or move it to the extension file as a stored property won't work in extensions — keep it in `ReaderStore.swift` as `var tocScrollRequestCounter = 0`.

- [ ] **Step 3: Wire it all up in ContentView**

Update `handleTOCHeadingSelection`:

```swift
    private func handleTOCHeadingSelection(_ heading: TOCHeading) {
        readerStore.scrollToTOCHeading(heading)
    }
```

Pass `tocScrollRequest` to the `MarkdownWebView`:

Find where `MarkdownWebView` is instantiated and add:
```swift
    tocScrollRequest: readerStore.tocScrollRequest
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/TOCHeading.swift minimark/Views/MarkdownWebView.swift minimark/ContentView.swift minimark/Stores/ReaderStore.swift minimark/Stores/Coordination/ReaderStore+TableOfContents.swift
git commit -m "feat(toc): implement scroll-to-heading dispatch (#158)"
```

---

### Task 10: Add keyboard shortcut and focused value

**Files:**
- Modify: `minimark/Support/ReaderFocusedActions.swift`
- Modify: `minimark/Commands/ReaderCommands.swift`
- Modify: `minimark/ContentView.swift`

- [ ] **Step 1: Add the focused value key and action type**

In `ReaderFocusedActions.swift`, add after `ReaderSourceEditingContextKey` (line 197):

```swift
struct ReaderToggleTOCAction {
    let canToggle: Bool
    let toggle: () -> Void

    func callAsFunction() {
        guard canToggle else { return }
        toggle()
    }
}

private struct ReaderToggleTOCActionKey: FocusedValueKey {
    typealias Value = ReaderToggleTOCAction
}
```

Add to the `FocusedValues` extension (after `readerSourceEditingContext`):

```swift
    var readerToggleTOC: ReaderToggleTOCAction? {
        get { self[ReaderToggleTOCActionKey.self] }
        set { self[ReaderToggleTOCActionKey.self] = newValue }
    }
```

- [ ] **Step 2: Add the menu item in ReaderCommands**

In `ReaderCommands.swift`, add `@FocusedValue(\.readerToggleTOC) private var toggleTOC` alongside the other focused values (around line 18).

In `body`, in the `CommandGroup(after: .toolbar)` block, add after the "Cycle Document View" button (after line 113):

```swift
            Divider()

            Button("Table of Contents") {
                toggleTOC?()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!(toggleTOC?.canToggle ?? false))
```

- [ ] **Step 3: Provide the focused value from ContentView**

In `ContentView.swift`, in the `interactionAwareView` method, add after the `.focusedValue(\.readerChangedRegionNavigation, ...)`:

```swift
        .focusedValue(
            \.readerToggleTOC,
            ReaderToggleTOCAction(
                canToggle: !readerStore.tocHeadings.isEmpty,
                toggle: { readerStore.toggleTOC() }
            )
        )
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add minimark/Support/ReaderFocusedActions.swift minimark/Commands/ReaderCommands.swift minimark/ContentView.swift
git commit -m "feat(toc): add Cmd+Shift+T keyboard shortcut (#158)"
```

---

### Task 11: Run full test suite and final build verification

**Files:** None (verification only)

- [ ] **Step 1: Run unit tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Run full debug build**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit any fixes if needed**

If any tests fail or build issues arise, fix them and commit.
