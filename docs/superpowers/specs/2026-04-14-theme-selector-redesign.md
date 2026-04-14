# Theme Selector Redesign

## Problem

The current theme selector in `ReaderSettingsView.swift` uses standard macOS `Picker` dropdowns for reader themes and syntax themes. This provides a poor browsing experience — you can't see what a theme looks like without selecting it, and the small preview card at the bottom of the form is disconnected from the selection controls.

## Design

Replace the picker-based theme section with a **three-column layout** inline in the existing settings view:

```
┌──────────────┬──────────────┬──────────────────────────┐
│ Reader Theme │ Syntax Theme │        Preview           │
│  (25%)       │  (25%)       │        (50%)             │
│              │              │                          │
│ ☀ Light      │ ■ Monokai   │  Chapter One             │
│ 🌙 Dark      │ ■ Dracula   │  It was a bright cold... │
│              │ ■ Nord      │                          │
│ ■ White/Black│ ■ GitHub    │  func greet(name:) {     │
│ ■ Light Gray │ ■ One Light │    print("Hello")        │
│ ■ Newspaper  │ ■ One Dark  │  }                       │
│ ■ Focus      │             │                          │
├──────────────┴──────────────┴──────────────────────────┤
│ Current: White/Black + Monokai      [Reset]  [Apply]   │
└─────────────────────────────────────────────────────────┘
```

### Column Layout

Proportions are defined in a single configurable constant for easy adjustment:

```swift
private enum ColumnLayout {
    static let selectorRatio: CGFloat = 0.25
    static let previewRatio: CGFloat = 0.50
}
```

### Column 1: Reader Themes

- **Segmented control** at the top: ☀ Light / 🌙 Dark, filtering the 11 `ReaderThemeKind` cases by `hasLightBackground`.
- **Scrollable list** of theme cards below. Each card shows:
  - A color swatch filled with the theme's background color.
  - Theme display name.
  - Short description tagline.
- Selected theme highlighted with a purple border.
- Clicking a theme **stages** it (updates the preview instantly but does not apply to reader windows).

### Column 2: Syntax Themes

- **Scrollable list** of all 12 `SyntaxThemeKind` cases. Each card shows:
  - A gradient color strip representing the palette.
  - Theme name.
- Selected theme highlighted with a purple border.
- **When the staged reader theme provides its own syntax highlighting** (`providesSyntaxHighlighting == true`), the entire column is replaced with a centered disabled-state message: *"Syntax highlighting is controlled by the active theme."* The staged syntax selection is preserved but hidden.

### Column 3: Preview

- Renders the existing `ThemePreviewCard` content (heading, body text, code block with syntax-colored tokens) using the **staged** reader theme and syntax theme.
- Updates instantly as the user browses — no need to press Apply to see the preview.

### Apply / Reset Bar

- Spans the full width below the three columns.
- **"Unsaved changes" indicator** appears when staged values differ from the currently applied values.
- **Apply button**: writes staged values to `ReaderSettingsStore`, which triggers the existing Combine pipeline to update all unlocked reader windows.
- **Reset button**: reverts staged values back to the currently applied values.
- **Current state label**: shows the currently applied reader + syntax theme names.

### Staging Mechanism

A new `@Observable` view model (e.g. `ThemeSelectorViewModel`) holds:

```swift
@ObservationIgnored private let settingsStore: ReaderSettingsStore
var stagedReaderTheme: ReaderThemeKind
var stagedSyntaxTheme: SyntaxThemeKind
var hasUnsavedChanges: Bool { ... }
```

- Initialized from `settingsStore.currentSettings`.
- The preview reads from staged values.
- Apply writes staged values back to `settingsStore.updateTheme()` / `settingsStore.updateSyntaxTheme()`.
- Reset copies current settings back to staged values.

### Theme-Controlled Syntax Behavior

When the staged reader theme's `ThemeDefinition.providesSyntaxHighlighting` is true:
- The syntax column shows a disabled overlay with explanation text.
- The previously staged syntax theme is preserved internally so it restores if the user switches back to a theme that doesn't control syntax.

### Locked Windows Hint

The existing locked windows hint from `ReaderSettingsView` is preserved and displayed in the apply bar area.

## Files to Modify

| File | Change |
|------|--------|
| `minimark/Views/ReaderSettingsView.swift` | Replace picker section with new three-column `ThemeSelectorView` |
| `minimark/Views/ThemeSelectorView.swift` (new) | Main three-column layout, staging logic, apply/reset |
| `minimark/Views/ThemeCardView.swift` (new) | Reusable card component for theme list items |
| `minimark/ViewModels/ThemeSelectorViewModel.swift` (new) | Staging state, apply/reset actions |

## Files Unchanged

- `ReaderSettingsStore.swift` — existing `updateTheme` / `updateSyntaxTheme` methods used as-is.
- All theme model files (`ReaderTheme.swift`, `SyntaxTheme.swift`, `ThemeDefinition.swift`, etc.).
- All specialized theme files (Amber, Green, etc.).
- Rendering pipeline (`ReaderStore+Rendering.swift`, `ReaderCSSFactory.swift`, etc.).
- `ThemePreviewCard` — reused as-is inside the preview column.

## Constraints

- Column proportions must be a single easily-configurable constant, not scattered magic numbers.
- No changes to the rendering or persistence pipeline — the staging VM calls the same `settingsStore` methods.
- Preserve the existing `syntaxHighlightingControlledByTheme` behavior.
- Preserve the locked windows hint.
- Must work within the existing `Form` / `.grouped` settings style on macOS.
