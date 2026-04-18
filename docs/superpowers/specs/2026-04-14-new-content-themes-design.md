# Design: Four New Content Themes

## Summary

Add four new reader themes — Gruvbox Dark, Gruvbox Light, Dracula, Monokai — that each define a color scheme with distinct header colors per heading level (h1/h2/h3). Syntax highlighting remains user-selectable and is not bundled with these themes. Clean, minimal: no custom fonts, effects, or JavaScript.

## Themes

### Gruvbox Dark
- **Type:** Dark
- **Background:** `#282828` | **Foreground:** `#EBDBB2`
- **Secondary fg:** `#BDAE93` | **Code bg:** `#1D2021` | **Border:** `#504945`
- **Link:** `#FE8019`
- **Headers:** h1 `#FB4934` (red), h2 `#B8BB26` (green), h3 `#83A598` (blue)
- **Change colors:** added `#B8BB26` on `#2A2820`, edited `#FABD2F` on `#2C2520`, deleted `#FB4934` on `#2C1E1E`
- **Syntax highlighting:** user-selectable (not bundled)

### Gruvbox Light
- **Type:** Light
- **Background:** `#FBF1C7` | **Foreground:** `#3C3836`
- **Secondary fg:** `#504945` | **Code bg:** `#EBDBB2` | **Border:** `#D5C4A1`
- **Link:** `#076678`
- **Headers:** h1 `#9D0006` (red), h2 `#79740E` (green), h3 `#076678` (blue)
- **Change colors:** added `#79740E` on `#D5C4A1`, edited `#B57614` on `#D5C4A1`, deleted `#9D0006` on `#E6C4C4`
- **Syntax highlighting:** user-selectable (not bundled)

### Dracula
- **Type:** Dark
- **Background:** `#282A36` | **Foreground:** `#F8F8F2`
- **Secondary fg:** `#BFC0D0` | **Code bg:** `#21222C` | **Border:** `#44475A`
- **Link:** `#8BE9FD`
- **Headers:** h1 `#FF79C6` (pink), h2 `#50FA7B` (green), h3 `#8BE9FD` (cyan)
- **Change colors:** added `#50FA7B` on `#1E3028`, edited `#BD93F9` on `#2A2838`, deleted `#FF79C6` on `#322030`
- **Syntax highlighting:** user-selectable (not bundled)

### Monokai
- **Type:** Dark
- **Background:** `#272822` | **Foreground:** `#F8F8F2`
- **Secondary fg:** `#CFCFC2` | **Code bg:** `#1E1F1C` | **Border:** `#3A3C33`
- **Link:** `#A6E22E`
- **Headers:** h1 `#F92672` (pink), h2 `#A6E22E` (green), h3 `#66D9EF` (cyan)
- **Change colors:** added `#A6E22E` on `#1E2618`, edited `#E6DB74` on `#2A2818`, deleted `#F92672` on `#2A1C1E`
- **Syntax highlighting:** user-selectable (not bundled)

## Architecture

Each theme is added through the existing content-theme flow: a case in `ReaderThemeKind` wired through the shared `ThemeDefinition` switch with `providesSyntaxHighlighting: false`. No per-theme Swift files are needed. Syntax highlighting remains user-selectable.

### Modified files
- `ReaderTheme.swift` — add 4 cases to `ReaderThemeKind`, 4 color sets to `ReaderTheme.theme(for:)`, 3 dark entries to `isDark`, 4 header color fields to `ReaderTheme` struct, header CSS variables to `cssVariables(baseFontSize:)`
- `ThemeDefinition.swift` — add 4 mappings in the shared `themeDefinition` computed property
- `ReaderCSSThemeGenerator.swift` — apply `--reader-h1`, `--reader-h2`, `--reader-h3` variables to h1/h2/h3 elements in structural CSS

### Header color mechanism
- Add `h1Hex`, `h2Hex`, `h3Hex` fields to `ReaderTheme` struct
- Emit them as `--reader-h1`, `--reader-h2`, `--reader-h3` CSS variables
- Apply in structural CSS: `h1 { color: var(--reader-h1); }` etc.
- Existing themes use the foreground color for all headers (no visual change)

### Custom CSS
Each theme's `customCSS` is empty (`nil`). The header colors are handled via the CSS variable system, not custom CSS — consistent with how other colors work.

## Testing
- Update `ThemeDefinitionTests` to verify all 4 new themes have valid definitions (no syntax highlighting bundled, correct color values)
- Verify all existing tests pass (no regressions)
