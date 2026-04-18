# Theme Selector Redesign

## Problem

The previous settings UI used compact `Picker` controls for reader and syntax themes.
That made browsing themes slow because users could not compare options visually before
committing a change.

## Implemented Design

The Theme section now uses a dedicated three-column selector embedded in
`ReaderSettingsView`:

1. Reader theme column with light/dark filtering tabs.
2. Syntax theme column with cards (or a disabled explanatory state when syntax is
   controlled by the selected reader theme).
3. Live preview column showing staged changes immediately.

An apply bar below the columns shows current applied values, unsaved state,
window-lock hints, and `Reset` / `Apply` actions.

## Column Sizing Strategy

The implementation uses minimum widths, not fixed proportional ratios.
Columns are configured through `ThemeSelectorColumnWidths` in
`minimark/Views/ThemeSelectorView.swift`:

```swift
struct ThemeSelectorColumnWidths {
    static let readerMin: CGFloat = 180
    static let syntaxMin: CGFloat = 180
    static let previewMin: CGFloat = 320
}
```

Each column uses `.frame(minWidth: ..., maxWidth: .infinity)` so the layout can
expand with the available window width while preserving practical minimums.

## State and Data Flow

Staging state is held directly in `ThemeSelectorView` via `@State`:

- `stagedReaderTheme`
- `stagedSyntaxTheme`
- `selectedBackgroundTab`

Behavior:

- Preview reads staged values immediately.
- `Apply` writes staged values to `ReaderSettingsStore` via
  `updateTheme` / `updateSyntaxTheme`.
- `Reset` restores staged values from currently applied settings.

No separate `ThemeSelectorViewModel` file is used.

## Preview Behavior

`ThemePreviewCard` is used by `ThemeSelectorView` and now includes explicit reader
text-color samples in addition to heading/body/code examples.

## Settings Layout

`ReaderSettingsView` uses a custom `ScrollView` + section container layout for this
redesign, not the prior `Form` / `.grouped` structure.

Accessibility labels are preserved on controls, including row pickers and toggle in
the redesigned layout.

## Files Changed

| File | Role |
|------|------|
| `minimark/Views/ReaderSettingsView.swift` | Integrates settings sections and embeds `ThemeSelectorView` |
| `minimark/Views/ThemeSelectorView.swift` | Three-column selector, staged state, apply/reset behavior |
| `minimark/Views/ThemeCardView.swift` | Reusable reader and syntax theme card rows |
| `minimarkTests/Core/ThemeSelectorLayoutAndPreviewTests.swift` | Verifies column minimum widths and preview sample output |

## Constraints Preserved

- No rendering pipeline changes required.
- Existing `ReaderSettingsStore` update methods remain the integration point.
- Syntax-theme override behavior from reader theme definitions remains intact.
- Locked-window hint remains visible in the apply bar.
