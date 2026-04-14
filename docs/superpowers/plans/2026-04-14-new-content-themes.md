# New Content Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four new reader themes (Gruvbox Dark, Gruvbox Light, Dracula, Monokai) as content themes, while preserving user-selected syntax highlighting and supporting distinct per-level header colors.

**Architecture:** Each theme is added through the existing content-theme flow rather than the "advanced theme" pattern. Syntax highlighting remains user-selectable and is not bundled into the theme definitions. Header colors are passed through new `h1Hex`/`h2Hex`/`h3Hex` fields on `ReaderTheme`, emitted as CSS variables, and applied in the structural CSS.

**Tech Stack:** Swift, SwiftUI, CSS variables.

---

### Task 1: Add header color fields to ReaderTheme

**Files:**
- Modify: `minimark/Models/ReaderTheme.swift`

- [ ] **Step 1: Add `h1Hex`, `h2Hex`, `h3Hex` fields to `ReaderTheme` struct**

Add after the `hasLightBackground` field (line 89):

```swift
    let h1Hex: String?
    let h2Hex: String?
    let h3Hex: String?
```

- [ ] **Step 2: Add header color parameters to all existing `ReaderTheme(...)` initializers**

For all existing themes in `ReaderTheme.theme(for:)`, add `h1Hex: nil, h2Hex: nil, h3Hex: nil` to each `ReaderTheme(...)` call. This preserves existing behavior (headers use foreground color via CSS fallback).

- [ ] **Step 3: Emit header CSS variables from `cssVariables(baseFontSize:)`**

In the `cssVariables` method, add after the `--reader-font-size` line (before the closing `}`):

```swift
          \(h1Hex.map { "--reader-h1: \($0);" } ?? "")
          \(h2Hex.map { "--reader-h2: \($0);" } ?? "")
          \(h3Hex.map { "--reader-h3: \($0);" } ?? "")
```

- [ ] **Step 4: Commit**

```bash
git add minimark/Models/ReaderTheme.swift
git commit -m "Add optional header color fields (h1/h2/h3) to ReaderTheme"
```

---

### Task 2: Apply header CSS variables in structural CSS

**Files:**
- Modify: `minimark/Support/ReaderCSSThemeGenerator.swift`

- [ ] **Step 1: Add header color rules to the structural CSS**

In `generateCSS`, add after the `.markdown-body blockquote li` block (after line 329, before the `img, video, canvas, svg` block):

```swift
        .markdown-body h1 {
          color: var(--reader-h1, var(--reader-fg));
        }

        .markdown-body h2 {
          color: var(--reader-h2, var(--reader-fg));
        }

        .markdown-body h3 {
          color: var(--reader-h3, var(--reader-fg));
        }

        .markdown-body h4,
        .markdown-body h5,
        .markdown-body h6 {
          color: var(--reader-fg);
        }
```

The `var(--reader-h1, var(--reader-fg))` pattern falls back to foreground color when the header variable is not set, so existing themes are unaffected.

- [ ] **Step 2: Commit**

```bash
git add minimark/Support/ReaderCSSThemeGenerator.swift
git commit -m "Apply header color CSS variables in structural CSS with foreground fallback"
```

---

### Task 3: Add 4 new cases to ReaderThemeKind

**Files:**
- Modify: `minimark/Models/ReaderTheme.swift`

- [ ] **Step 1: Add enum cases**

Add after `case gameBoy` (line 14):

```swift
    case gruvboxDark
    case gruvboxLight
    case dracula
    case monokai
```

- [ ] **Step 2: Add to `isDark` switch**

In the `isDark` property, add these 3 cases to the `true` branch (the existing `case .whiteOnBlack, ...` line):

```swift
        case .whiteOnBlack, .lightGreyOnDarkGrey, .amberTerminal, .greenTerminal, .greenTerminalStatic, .commodore64, .gruvboxDark, .dracula, .monokai:
```

Add `gruvboxLight` to the `false` branch:

```swift
        case .blackOnWhite, .darkGreyOnLightGrey, .newspaper, .focus, .gameBoy, .gruvboxLight:
```

- [ ] **Step 3: Add display names**

In `displayName`, add after the `gameBoy` case:

```swift
        case .gruvboxDark:
            return "Gruvbox Dark"
        case .gruvboxLight:
            return "Gruvbox Light"
        case .dracula:
            return "Dracula"
        case .monokai:
            return "Monokai"
```

- [ ] **Step 4: Add color sets to `ReaderTheme.theme(for:)`**

Add after the `gameBoy` case, before the closing `}`:

```swift
        case .gruvboxDark:
            return ReaderTheme(
                kind: .gruvboxDark,
                backgroundHex: "#282828",
                foregroundHex: "#EBDBB2",
                secondaryForegroundHex: "#BDAE93",
                codeBackgroundHex: "#1D2021",
                borderHex: "#504945",
                linkHex: "#FE8019",
                changedBlockHex: "#2A2820",
                changeAddedHex: "#B8BB26",
                changeEditedHex: "#FABD2F",
                changeDeletedHex: "#FB4934",
                hasLightBackground: false,
                h1Hex: "#FB4934",
                h2Hex: "#B8BB26",
                h3Hex: "#83A598"
            )
        case .gruvboxLight:
            return ReaderTheme(
                kind: .gruvboxLight,
                backgroundHex: "#FBF1C7",
                foregroundHex: "#3C3836",
                secondaryForegroundHex: "#504945",
                codeBackgroundHex: "#EBDBB2",
                borderHex: "#D5C4A1",
                linkHex: "#076678",
                changedBlockHex: "#D5C4A1",
                changeAddedHex: "#79740E",
                changeEditedHex: "#B57614",
                changeDeletedHex: "#9D0006",
                hasLightBackground: true,
                h1Hex: "#9D0006",
                h2Hex: "#79740E",
                h3Hex: "#076678"
            )
        case .dracula:
            return ReaderTheme(
                kind: .dracula,
                backgroundHex: "#282A36",
                foregroundHex: "#F8F8F2",
                secondaryForegroundHex: "#BFC0D0",
                codeBackgroundHex: "#21222C",
                borderHex: "#44475A",
                linkHex: "#8BE9FD",
                changedBlockHex: "#1E3028",
                changeAddedHex: "#50FA7B",
                changeEditedHex: "#BD93F9",
                changeDeletedHex: "#FF79C6",
                hasLightBackground: false,
                h1Hex: "#FF79C6",
                h2Hex: "#50FA7B",
                h3Hex: "#8BE9FD"
            )
        case .monokai:
            return ReaderTheme(
                kind: .monokai,
                backgroundHex: "#272822",
                foregroundHex: "#F8F8F2",
                secondaryForegroundHex: "#CFCFC2",
                codeBackgroundHex: "#1E1F1C",
                borderHex: "#3A3C33",
                linkHex: "#A6E22E",
                changedBlockHex: "#1E2618",
                changeAddedHex: "#A6E22E",
                changeEditedHex: "#E6DB74",
                changeDeletedHex: "#F92672",
                hasLightBackground: false,
                h1Hex: "#F92672",
                h2Hex: "#A6E22E",
                h3Hex: "#66D9EF"
            )
```

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/ReaderTheme.swift
git commit -m "Add Gruvbox Dark/Light, Dracula, Monokai reader theme kinds and color sets"
```

---

### Task 4: Wire themes into ThemeDefinition mapping

**Files:**
- Modify: `minimark/Models/ThemeDefinition.swift`

- [ ] **Step 1: Add the 4 new cases to the shared simple-theme branch**

In `themeDefinition`, extend the existing simple-theme `case` to include all 4 new kinds:

```swift
case .blackOnWhite, .whiteOnBlack, .darkGreyOnLightGrey, .lightGreyOnDarkGrey,
     .gruvboxDark, .gruvboxLight, .dracula, .monokai:
    return ThemeDefinition(
        kind: self,
        displayName: displayName,
        colors: ReaderTheme.theme(for: self),
        customCSS: nil,
        customJavaScript: nil,
        providesSyntaxHighlighting: false,
        syntaxCSS: nil,
        syntaxPreviewPalette: nil
    )
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/ThemeDefinition.swift
git commit -m "Wire Gruvbox Dark/Light, Dracula, Monokai into shared simple ThemeDefinition path"
```

---

### Task 5: Add tests for new themes

**Files:**
- Modify: `minimarkTests/Rendering/ThemeDefinitionTests.swift`

- [ ] **Step 1: Add tests for each new theme**

Add tests that verify each theme has the correct definition (no built-in syntax highlighting), correct color values, and emits the expected header CSS variables:

```swift
func testGruvboxDarkThemeDefinition() {
    let definition = ReaderThemeKind.gruvboxDark.themeDefinition
    XCTAssertEqual(definition.displayName, "Gruvbox Dark")
    XCTAssertTrue(definition.kind.isDark)
    XCTAssertNil(definition.customCSS)
    XCTAssertNil(definition.customJavaScript)
    XCTAssertFalse(definition.providesSyntaxHighlighting)
    XCTAssertNil(definition.syntaxCSS)
    XCTAssertNil(definition.syntaxPreviewPalette)
}

func testNewThemesCSSContainsHeaderVariables() {
    let factory = ReaderCSSFactory()
    let newThemes: [ReaderThemeKind] = [.gruvboxDark, .gruvboxLight, .dracula, .monokai]
    for kind in newThemes {
        let theme = kind.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        let colors = theme.colors
        XCTAssertTrue(css.contains("--reader-h1: \(colors.h1Hex!)"), "Missing h1 variable for \(kind)")
        XCTAssertTrue(css.contains("--reader-h2: \(colors.h2Hex!)"), "Missing h2 variable for \(kind)")
        XCTAssertTrue(css.contains("--reader-h3: \(colors.h3Hex!)"), "Missing h3 variable for \(kind)")
    }
}

func testNewThemesUseSelectedSyntaxTheme() {
    let factory = ReaderCSSFactory()
    let theme = ReaderThemeKind.gruvboxDark.themeDefinition
    let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
    XCTAssertTrue(css.contains("#D73A49"), "Should contain GitHub keyword color from selected syntax theme")
}
```

- [ ] **Step 2: Commit**

```bash
git add minimarkTests/Rendering/ThemeDefinitionTests.swift
git commit -m "Add tests for Gruvbox Dark/Light, Dracula, Monokai themes and header color system"
```

---

### Task 6: Run full test suite and verify

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`
Expected: All tests pass, including new theme tests and existing tests (no regressions).
