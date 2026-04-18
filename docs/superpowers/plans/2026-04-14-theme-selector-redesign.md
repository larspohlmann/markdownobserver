# Theme Selector Redesign — Implementation Plan (As Implemented)

## Goal

Replace picker-only theme controls in `ReaderSettingsView` with a clearer, staged,
three-column selector that supports browsing reader and syntax themes with live
preview before applying.

## Final Architecture

- `ThemeSelectorView` owns staging state directly via `@State`.
- `ThemeSelectorView` renders:
  - reader-theme column (with light/dark segmentation)
  - syntax-theme column (or disabled state when theme controls syntax)
  - preview column (`ThemePreviewCard`)
  - apply/reset bar with unsaved state and locked-window hint
- `ReaderSettingsStore` remains the write target for committed changes:
  - `updateTheme(...)`
  - `updateSyntaxTheme(...)`

## Layout Strategy

The shipped layout uses minimum widths rather than ratio-based geometry:

```swift
struct ThemeSelectorColumnWidths {
    static let readerMin: CGFloat = 180
    static let syntaxMin: CGFloat = 180
    static let previewMin: CGFloat = 320
}
```

Each column expands with `.frame(minWidth: ..., maxWidth: .infinity)`.

## Files and Responsibilities

| Path | Responsibility |
|------|----------------|
| `minimark/Views/ThemeSelectorView.swift` | Staged state, three-column layout, apply/reset behavior |
| `minimark/Views/ThemeCardView.swift` | Reader and syntax card rows |
| `minimark/Views/ReaderSettingsView.swift` | Hosts selector in custom sectioned settings layout |
| `minimarkTests/Core/ThemeSelectorLayoutAndPreviewTests.swift` | Verifies column width constants and preview sample behavior |

## Notable Decisions

1. Keep state local to `ThemeSelectorView`.
   - A separate `ThemeSelectorViewModel` was not introduced because the staged state
     surface is small and view-local.
2. Use minimum-width constraints instead of 25/25/50 ratio constants.
   - This behaves better under resizing while keeping usability minimums.
3. Keep the custom `ScrollView`-based settings containers in `ReaderSettingsView`.
   - No return to `Form` / `.grouped` style.

## Accessibility Notes

Controls in the redesigned settings rows use meaningful labels (including visually
hidden labels on pickers/toggle) so VoiceOver can identify them.

## Verification Checklist

- Build succeeds for `minimark` scheme in Debug.
- Theme selector columns respect configured minimum widths.
- Staged theme changes update preview immediately.
- Apply writes changes via existing store update methods.
- Reset restores staged values from currently applied settings.
