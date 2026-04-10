# Table of Contents Overlay — Design Spec

**Issue:** [#158](https://github.com/larspohlmann/markdownobserver/issues/158)
**Date:** 2026-04-06

## Summary

Add a Table of Contents (TOC) button to the utility rail that opens a popover listing the document's h1–h3 headings. Clicking a heading scrolls to it and dismisses the popover. Available in all view modes (preview, split, source). Hidden when the document has no headings. Toggled via `Cmd+Shift+T`.

## Data Model

```swift
struct TOCHeading: Identifiable, Equatable {
    let id: String        // element ID (slug from installHeadingIDs)
    let level: Int        // 1, 2, or 3
    let title: String     // heading text
    let sourceLine: Int?  // data-src-line-start (for source mode scrolling)
}
```

Stored as `[TOCHeading]` on `ReaderStore`. Updated whenever the document renders or source text changes.

## Heading Extraction — JavaScript

Two extraction paths, both posting to a new `minimarkTOC` message handler.

### Preview/Split mode

After markdown-it renders, query the DOM for heading elements. Called at the end of the existing render flow in `markdownobserver-runtime.js`.

```javascript
function extractHeadings() {
    const headings = document.querySelectorAll('h1, h2, h3');
    const result = Array.from(headings).map(el => ({
        id: el.id,
        level: parseInt(el.tagName[1]),
        title: el.textContent.trim(),
        sourceLine: parseInt(el.getAttribute('data-src-line-start')) || null
    }));
    window.webkit.messageHandlers.minimarkTOC.postMessage(result);
}
```

### Source mode

Regex scan of raw markdown text. Runs in the source editing HTML page on load and after edits. Handles code fences to avoid false positives.

```javascript
function extractHeadingsFromSource(text) {
    const lines = text.split('\n');
    const result = [];
    let inCodeFence = false;
    for (let i = 0; i < lines.length; i++) {
        if (/^```|^~~~/.test(lines[i])) { inCodeFence = !inCodeFence; continue; }
        if (inCodeFence) continue;
        const match = lines[i].match(/^(#{1,3})\s+(.+)/);
        if (match) {
            result.push({
                id: '', level: match[1].length,
                title: match[2].trim(), sourceLine: i + 1
            });
        }
    }
    window.webkit.messageHandlers.minimarkTOC.postMessage(result);
}
```

## Swift Integration

### Message handler

Add `minimarkTOC` to `MarkdownWebView.Coordinator` alongside the existing `minimarkScrollSync`, `minimarkSourceEdit`, and `minimarkSourceEditorDiagnostic` handlers. Parses the JSON array into `[TOCHeading]` and calls back to the store.

### Store extension — `ReaderStore+TableOfContents.swift`

- `var tocHeadings: [TOCHeading] = []` — updated from the message handler
- `var isTOCVisible: Bool = false` — toggled by button/shortcut
- `func toggleTOC()` — flips visibility
- `func scrollToTOCHeading(_ heading: TOCHeading)` — dispatches scroll, closes popover

### Scroll dispatch

- **Preview/Split:** evaluate JS `document.getElementById(id).scrollIntoView({ behavior: 'smooth', block: 'start' })` via the existing `scrollToFragment` pattern in `MarkdownWebView.Coordinator`.
- **Source:** scroll the textarea/CodeMirror to `heading.sourceLine` via JS. In source mode, `heading.id` is empty (no rendered DOM), so scrolling relies exclusively on `sourceLine`.

## UI — TOC Button

**Placement:** `ContentUtilityRail`, below the edit group, separated by a `groupSeparator`.

- Same `railButtonBackground` style as existing buttons
- SF Symbol: `list.bullet.indent`
- Hidden when `tocHeadings` is empty
- Accessibility: label "Table of Contents", value "Visible"/"Hidden"

## UI — TOC Popover

**Anchor:** `.popover(isPresented:arrowEdge: .trailing)` — arrow points right toward the rail, popover opens to the left.

**Layout:**
- `ScrollView` wrapping a `LazyVStack(alignment: .leading, spacing: 0)`
- Content-hugging height: sizes to content, max ~400pt before scrolling
- Width: `minWidth: 200, idealWidth: 260, maxWidth: 320`

**Heading rows:**
- Each row is a `Button` (plain style) that scrolls to the heading and dismisses the popover
- Indentation: `CGFloat(heading.level - 1) * 16` left padding
- Font: `.system(size: 13, weight: .semibold)` for h1, `.system(size: 12)` for h2/h3
- Hover effect via `PointingHandCursor` modifier
- Vertical padding: 5pt per row
- Horizontal padding: 12pt

**Styling:** follows `FolderWatchToolbarButton` popover patterns (padding, section headers, colors).

## Keyboard Shortcut

`Cmd+Shift+T` in `ReaderCommands.swift`, inside the `CommandGroup(after: .toolbar)` block.

New `@FocusedValue`:
- `\.readerToggleTOC` — closure that toggles `isTOCVisible`
- Disabled when `tocHeadings` is empty

Focused value provided from the same view that hosts `ContentUtilityRail`.

## Files to Create/Modify

| File | Action |
|------|--------|
| `minimark/Models/TOCHeading.swift` | **Create** — model struct |
| `minimark/Stores/Coordination/ReaderStore+TableOfContents.swift` | **Create** — TOC state + actions |
| `minimark/Views/Content/TOCPopoverView.swift` | **Create** — popover UI |
| `minimark/Views/Content/ContentUtilityRail.swift` | **Modify** — add TOC button |
| `minimark/Views/MarkdownWebView.swift` | **Modify** — add `minimarkTOC` message handler |
| `minimark/App/Resources/markdownobserver-runtime.js` | **Modify** — add `extractHeadings()` call after render |
| `minimark/Commands/ReaderCommands.swift` | **Modify** — add `Cmd+Shift+T` shortcut |
| `minimark/Support/MarkdownSourceHTMLRenderer.swift` | **Modify** — add source-mode heading extraction JS |

## Testing

- Unit test `TOCHeading` model
- Unit test source-mode heading extraction (regex parsing edge cases: code fences, empty headings, levels > 3 ignored)
- Integration: verify heading list updates when document changes
- Integration: verify scroll-to-heading dispatches correct JS
- Manual: verify popover appearance, indentation, dismiss behavior, keyboard shortcut
