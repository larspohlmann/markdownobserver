# Loading Spinner Overlay When Switching Tabs

**Issue:** [#59](https://github.com/larspohlmann/markdownobserver/issues/59)
**Date:** 2026-04-01

## Problem

When switching to a tab whose file hasn't been loaded yet (deferred document) or opening a new file, `openFile` runs synchronously on the main actor — file I/O, markdown rendering, and all `@Published` updates happen in one blocking call. The tab doesn't visually switch until all of that completes, making the UI feel unresponsive.

## Goal

Decouple the tab switch from content loading so the UI stays responsive. The tab switches immediately, a styled spinner overlay appears over the content area while loading, and it disappears when content is ready.

## Design

### State machine change

Add a `.loading` case to `ReaderDocumentLoadState`:

```
.deferred ──► .loading ──► .ready
                       └──► .settlingAutoOpen

.ready ──► .loading ──► .ready  (normal file open)
                    └──► .settlingAutoOpen
```

The overlay displays for both `.loading` and `.settlingAutoOpen`.

### Async yield pattern

The core mechanism is a thin async wrapper around the existing synchronous `openFile`:

1. Set `documentLoadState = .loading` — triggers SwiftUI to show the overlay
2. `await Task.yield()` — yields to the run loop so SwiftUI gets one render pass
3. Call existing synchronous `openFile(at:...)` — which ends in `.ready` or `.settlingAutoOpen`

This wrapper method (`openFileWithLoadingState`) lives in `ReaderStore+DocumentOpenFlow.swift` alongside the existing `openFile`.

### Call site changes

**Deferred tab switch (`selectDocument`):**
- `selectDocument` sets `selectedDocumentID` and calls `bindSelectedStore()` immediately (tab switches visually)
- If the store is deferred, it dispatches a `Task` that calls `materializeDeferredDocument()`, which now uses `openFileWithLoadingState` internally
- The `Task` ensures the yield happens after the selection update

**Normal file open (`openDocumentInSelectedSlot` and similar):**
- These callers also use `openFileWithLoadingState` so that any file open shows the spinner briefly

### Overlay changes

`DocumentLoadingOverlay` is parameterized with a message string:
- `.loading` state: "Loading document..." with just the spinner and headline (no subtitle)
- `.settlingAutoOpen` state: keeps existing "Waiting for file contents..." text with subtitle

`ContentView.shouldShowDocumentLoadingOverlay` broadens to: `documentLoadState == .loading || documentLoadState == .settlingAutoOpen`.

## Files changed

| File | Change |
|---|---|
| `minimark/Stores/Types/ReaderStoreTypes.swift` | Add `.loading` case to `ReaderDocumentLoadState` |
| `minimark/Stores/Coordination/ReaderStore+DocumentOpenFlow.swift` | Add async `openFileWithLoadingState(...)` wrapper; update `materializeDeferredDocument` to use it |
| `minimark/Stores/ReaderSidebarDocumentController.swift` | Make deferred materialization in `selectDocument` dispatch via `Task` so selection + binding happen immediately |
| `minimark/ContentView.swift` | Broaden `shouldShowDocumentLoadingOverlay` to include `.loading` |
| `minimark/Views/Content/ContentDocumentSurfaceViews.swift` | Parameterize `DocumentLoadingOverlay` with message/subtitle |
| Existing tests | Update assertions that check `documentLoadState` transitions to account for `.loading` |
| New tests | Verify `.loading` is set before file I/O begins; verify it clears to `.ready` or `.settlingAutoOpen` after |

## Testing strategy

- Unit test: `materializeDeferredDocument` sets `.loading` before performing I/O
- Unit test: `openFileWithLoadingState` transitions from `.loading` to `.ready`
- Unit test: normal file open through `openFileWithLoadingState` also shows `.loading` transiently
- Existing deferred loading tests updated for the new intermediate state
