# Code Block Language Pill & Copy-to-Clipboard

## Summary

Add a language pill (top-right corner of fenced code blocks) and a copy-to-clipboard action to every code block in the reader webview. The pill shows the detected language name in lowercase; if no language is detected, a clipboard icon is shown instead. Clicking either copies the pure code content to the clipboard and shows a brief "Copied!" toast.

## Motivation

Code blocks currently have no language indicator or copy mechanism. Users cannot tell at a glance what language a block is written in, and copying code requires manual text selection — awkward for multi-line blocks.

## Design

### Approach

Pure JavaScript + CSS inside the WKWebView. No Swift-side changes beyond updating the JS and CSS generators that already inject into the webview.

### Rendering pipeline change

After `hljs.highlightAll()` and `annotateCodeBlockLines()` complete in `markdownobserver-runtime.js`, a new function `addCodeBlockOverlays()` runs. It:

1. Queries all `<pre>` elements containing a `<code>` child
2. For each, makes the `<pre>` `position: relative` and injects a `<button>` overlay in the top-right corner
3. Determines the overlay type:
   - **Has language**: if `<code>` has a class matching `language-xxx` (set by highlight.js), extract `xxx` and display it as lowercase text in a pill
   - **No language**: display a small clipboard SVG icon

### Copy behavior

- On click, extract the **pure code text** from the `<code>` element:
  - Use `textContent` to strip all HTML (including inline-diff markers like `.reader-inline-diff-removed`)
  - Trim leading/trailing whitespace
  - This ensures no diff noise or annotation markup enters the clipboard
- Copy via `navigator.clipboard.writeText()`
- Show a "Copied!" toast notification above the pill, auto-dismiss after 1.5s

### Visual design

- **Pill (has language)**: background uses `--reader-code-bg` (code block background), border `1px solid var(--reader-border)`, small font, rounded corners, opacity 0.7 → 1 on hover
- **Icon button (no language)**: same background/border styling, contains an SVG clipboard icon
- **Toast**: small text appearing above the pill with a CSS fade-in/out animation
- **All styling** uses existing CSS custom properties, so it adapts to every reader theme and syntax theme automatically

### Files changed

| File | Change |
|------|--------|
| `minimark/App/Resources/markdownobserver-runtime.js` | Add `addCodeBlockOverlays()` function, called after `annotateCodeBlockLines()` in `renderMarkdown()` |
| `minimark/Support/ReaderCSSThemeGenerator.swift` | Add CSS rules for overlay, pill, icon button, and toast |

### What is NOT changed

- No Swift view/controller changes
- No changes to highlight.js or markdown-it configuration
- No changes to the HTML document template
- No new dependencies

## Edge cases

- **Inline-diff view**: code blocks may contain diff markup (`reader-inline-diff-removed` spans). The copy function uses `textContent` which strips all markup automatically.
- **Empty code blocks**: skipped (no overlay injected)
- **Theme-provided syntax CSS** (AmberTerminal, GreenTerminal, etc.): inherits styling via CSS variables — no special handling needed
- **Content Security Policy**: the existing CSP allows `style-src 'unsafe-inline'` and clipboard API does not require CSP changes
- **In-place updates**: `addCodeBlockOverlays()` must also run when `__minimarkUpdateRenderedMarkdown` triggers a re-render
