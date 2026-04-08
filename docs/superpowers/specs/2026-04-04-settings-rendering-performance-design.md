# Fix UI Freezes on Settings Changes

**Issue:** [#136](https://github.com/larspohlmann/markdownobserver/issues/136)

## Problem

When changing theme, font size, or syntax theme, the app freezes because every settings change triggers **3 × N** synchronous renders on the main thread:

- `WindowAppearanceController` publishes 3 separate `@Published` properties (`effectiveTheme`, `effectiveFontSize`, `effectiveSyntaxTheme`), each firing SwiftUI's `.onChange` independently
- Each `.onChange` calls `reapplyAppearance()`, which iterates **all N sidebar documents** and calls `renderWithAppearance()` synchronously
- CSS generation (`ReaderCSSThemeGenerator.makeCSS`) rebuilds a multi-KB string from scratch on every call with no caching
- Deferred documents (not yet loaded) still run the full pipeline for nothing

## Design

### 1. Coalesce WindowAppearanceController into a single published value

Replace three `@Published` properties with one:

```swift
@Published private(set) var effectiveAppearance: LockedAppearance
```

`LockedAppearance` already exists with the right fields (`readerTheme`, `baseFontSize`, `syntaxTheme`) and already conforms to `Equatable`.

The Combine sink assigns the struct once. The three `.onChange` handlers in `ReaderWindowRootView` collapse to one:

```swift
.onChange(of: appearanceController.effectiveAppearance) { _, _ in
    reapplyAppearance()
}
```

Computed properties provide backwards-compatible access where individual values are read:

```swift
var effectiveTheme: ReaderThemeKind { effectiveAppearance.readerTheme }
var effectiveFontSize: Double { effectiveAppearance.baseFontSize }
var effectiveSyntaxTheme: SyntaxThemeKind { effectiveAppearance.syntaxTheme }
```

`lock()`, `unlock()`, `restore(from:)`, and `lockedAppearance` adapt to use the struct directly.

**Result:** 1 `.onChange` fire per settings change instead of 3.

### 2. Render only the selected document; mark others dirty

`reapplyAppearance()` changes from iterating all documents to:

1. Call `renderWithAppearance()` on `selectedDocument` only — the user sees this immediately
2. Call `setAppearanceOverride()` (already exists, sets override without rendering) on all other documents
3. Set a `needsAppearanceRender` flag on non-selected documents

When a document becomes selected (`.onChange(of: sidebarDocumentController.selectedDocumentID)`), if `needsAppearanceRender` is true, render it then and clear the flag.

The `needsAppearanceRender` flag lives on `ReaderStore` as a simple `Bool` property. It is set to `true` by `setAppearanceOverride()` implicitly (any call to `setAppearanceOverride` without a subsequent render means the document is dirty). It is cleared by `renderWithAppearance()` and `renderCurrentMarkdown()`.

**Result:** 1 render per settings change (the visible document) instead of N.

### 3. Skip deferred documents

Guard the rendering call site in `reapplyAppearance()` with `hasOpenDocument` — deferred documents have empty `sourceMarkdown` and produce no meaningful output. They still receive `setAppearanceOverride()` so they render with correct appearance when eventually loaded.

### 4. Cache CSS generation

Add a last-result cache to `ReaderCSSFactory`:

```swift
private var cachedCSS: (theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double, css: String)?

func makeCSS(theme: ThemeDefinition, syntaxTheme: SyntaxThemeKind, baseFontSize: Double) -> String {
    if let cached = cachedCSS,
       cached.theme == theme,
       cached.syntaxTheme == syntaxTheme,
       cached.baseFontSize == baseFontSize {
        return cached.css
    }
    let css = ReaderCSSThemeGenerator.makeCSS(theme: theme, syntaxTheme: syntaxTheme, baseFontSize: baseFontSize)
    cachedCSS = (theme, syntaxTheme, baseFontSize, css)
    return css
}
```

This requires `ReaderCSSFactory` to become a `class` (or use a mutable stored property pattern) since it's currently a `struct`. Alternatively, make the cache `static` on `ReaderCSSThemeGenerator`.

For this to work, `ThemeDefinition` needs `Equatable` conformance (check if it already has it; if not, add it).

**Result:** CSS generated once per unique appearance triple, not once per document.

## Net effect

| Metric | Before | After |
|--------|--------|-------|
| Renders per theme change | 3 × N | 1 |
| CSS generations per change | 3 × N | 1 (cached) |
| Deferred doc overhead | Full pipeline | None |
| Lazy render on selection | No | Yes |

## Testing strategy

- **WindowAppearanceController:** Verify a single settings change produces one `objectWillChange` notification (not three)
- **Lazy rendering:** Verify `reapplyAppearance` only renders the selected document and marks others dirty
- **Selection trigger:** Verify selecting a dirty document triggers rendering
- **CSS cache:** Verify cache hit returns same string, cache miss regenerates
- **Deferred skip:** Verify deferred documents are not rendered
- **Existing tests:** All current rendering and appearance controller tests continue to pass

## Files affected

- `minimark/Stores/WindowAppearanceController.swift` — coalesce to single `@Published`
- `minimark/Views/ReaderWindowRootView.swift` — collapse `.onChange` handlers, lazy rendering logic
- `minimark/Stores/ReaderStore.swift` — add `needsAppearanceRender` flag, clear on render
- `minimark/Support/ReaderCSSFactory.swift` — add CSS cache
- `minimark/Support/ReaderCSSThemeGenerator.swift` — possibly add cache here instead
- `minimark/Models/ThemeDefinition.swift` — add `Equatable` if missing
- `minimarkTests/Core/WindowAppearanceControllerTests.swift` — update for new API
- New test file for CSS cache and lazy rendering behavior
