# New Content Themes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four new reader themes (Gruvbox Dark, Gruvbox Light, Dracula, Monokai) with built-in syntax highlighting and distinct per-level header colors.

**Architecture:** Each theme follows the existing "advanced theme" pattern — a caseless enum in its own file providing a `ThemeDefinition` with `providesSyntaxHighlighting = true`. Header colors are passed through new `h1Hex`/`h2Hex`/`h3Hex` fields on `ReaderTheme`, emitted as CSS variables, and applied in the structural CSS.

**Tech Stack:** Swift, SwiftUI, CSS variables, highlight.js syntax tokens.

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

### Task 4: Create GruvboxDarkTheme.swift

**Files:**
- Create: `minimark/Models/GruvboxDarkTheme.swift`

- [ ] **Step 1: Create the theme file**

```swift
import Foundation

enum GruvboxDarkTheme {
    static let definition = ThemeDefinition(
        kind: .gruvboxDark,
        displayName: ReaderThemeKind.gruvboxDark.displayName,
        colors: ReaderTheme.theme(for: .gruvboxDark),
        customCSS: nil,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let syntaxCSS: String = """
    :root {
        --reader-mark-signal: #FABD2F;
        --reader-blockquote-accent: #FE8019;
        --reader-blockquote-bg: rgba(253, 128, 25, 0.08);
        --reader-blockquote-fg: #BDAE93;
    }

    pre {
      background: #1D2021;
      border: 1px solid #504945;
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
      color: #EBDBB2;
      background: transparent;
      display: block;
      padding: 0;
    }

    pre code .hljs-comment { color: #928374; }
    pre code .hljs-keyword { color: #FB4934; }
    pre code .hljs-string { color: #B8BB26; }
    pre code .hljs-number { color: #D3869B; }
    pre code .hljs-title { color: #83A598; }
    pre code .hljs-built_in { color: #FABD2F; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#EBDBB2",
        blockBackgroundHex: "#1D2021",
        blockBorderHex: "#504945",
        commentHex: "#928374",
        keywordHex: "#FB4934",
        stringHex: "#B8BB26",
        numberHex: "#D3869B",
        titleHex: "#83A598",
        builtInHex: "#FABD2F"
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/GruvboxDarkTheme.swift
git commit -m "Add Gruvbox Dark theme definition with syntax highlighting"
```

---

### Task 5: Create GruvboxLightTheme.swift

**Files:**
- Create: `minimark/Models/GruvboxLightTheme.swift`

- [ ] **Step 1: Create the theme file**

```swift
import Foundation

enum GruvboxLightTheme {
    static let definition = ThemeDefinition(
        kind: .gruvboxLight,
        displayName: ReaderThemeKind.gruvboxLight.displayName,
        colors: ReaderTheme.theme(for: .gruvboxLight),
        customCSS: nil,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let syntaxCSS: String = """
    :root {
        --reader-mark-signal: #B57614;
        --reader-blockquote-accent: #B57614;
        --reader-blockquote-bg: rgba(181, 118, 20, 0.08);
        --reader-blockquote-fg: #504945;
    }

    pre {
      background: #EBDBB2;
      border: 1px solid #D5C4A1;
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
      color: #3C3836;
      background: transparent;
      display: block;
      padding: 0;
    }

    pre code .hljs-comment { color: #928374; }
    pre code .hljs-keyword { color: #9D0006; }
    pre code .hljs-string { color: #79740E; }
    pre code .hljs-number { color: #8F3F71; }
    pre code .hljs-title { color: #076678; }
    pre code .hljs-built_in { color: #B57614; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#3C3836",
        blockBackgroundHex: "#EBDBB2",
        blockBorderHex: "#D5C4A1",
        commentHex: "#928374",
        keywordHex: "#9D0006",
        stringHex: "#79740E",
        numberHex: "#8F3F71",
        titleHex: "#076678",
        builtInHex: "#B57614"
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/GruvboxLightTheme.swift
git commit -m "Add Gruvbox Light theme definition with syntax highlighting"
```

---

### Task 6: Create DraculaTheme.swift

**Files:**
- Create: `minimark/Models/DraculaTheme.swift`

- [ ] **Step 1: Create the theme file**

```swift
import Foundation

enum DraculaTheme {
    static let definition = ThemeDefinition(
        kind: .dracula,
        displayName: ReaderThemeKind.dracula.displayName,
        colors: ReaderTheme.theme(for: .dracula),
        customCSS: nil,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let syntaxCSS: String = """
    :root {
        --reader-mark-signal: #F1FA8C;
        --reader-blockquote-accent: #BD93F9;
        --reader-blockquote-bg: rgba(189, 147, 249, 0.08);
        --reader-blockquote-fg: #BFC0D0;
    }

    pre {
      background: #21222C;
      border: 1px solid #44475A;
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
      color: #F8F8F2;
      background: transparent;
      display: block;
      padding: 0;
    }

    pre code .hljs-comment { color: #6272A4; }
    pre code .hljs-keyword { color: #FF79C6; }
    pre code .hljs-string { color: #F1FA8C; }
    pre code .hljs-number { color: #BD93F9; }
    pre code .hljs-title { color: #8BE9FD; }
    pre code .hljs-built_in { color: #50FA7B; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#F8F8F2",
        blockBackgroundHex: "#21222C",
        blockBorderHex: "#44475A",
        commentHex: "#6272A4",
        keywordHex: "#FF79C6",
        stringHex: "#F1FA8C",
        numberHex: "#BD93F9",
        titleHex: "#8BE9FD",
        builtInHex: "#50FA7B"
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/DraculaTheme.swift
git commit -m "Add Dracula theme definition with syntax highlighting"
```

---

### Task 7: Create MonokaiTheme.swift

**Files:**
- Create: `minimark/Models/MonokaiTheme.swift`

- [ ] **Step 1: Create the theme file**

```swift
import Foundation

enum MonokaiTheme {
    static let definition = ThemeDefinition(
        kind: .monokai,
        displayName: ReaderThemeKind.monokai.displayName,
        colors: ReaderTheme.theme(for: .monokai),
        customCSS: nil,
        customJavaScript: nil,
        providesSyntaxHighlighting: true,
        syntaxCSS: syntaxCSS,
        syntaxPreviewPalette: previewPalette
    )

    static let syntaxCSS: String = """
    :root {
        --reader-mark-signal: #E6DB74;
        --reader-blockquote-accent: #A6E22E;
        --reader-blockquote-bg: rgba(166, 226, 46, 0.06);
        --reader-blockquote-fg: #CFCFC2;
    }

    pre {
      background: #1E1F1C;
      border: 1px solid #3A3C33;
    }

    pre code,
    pre code.hljs,
    pre code[class*="language-"] {
      color: #F8F8F2;
      background: transparent;
      display: block;
      padding: 0;
    }

    pre code .hljs-comment { color: #75715E; }
    pre code .hljs-keyword { color: #F92672; }
    pre code .hljs-string { color: #E6DB74; }
    pre code .hljs-number { color: #AE81FF; }
    pre code .hljs-title { color: #A6E22E; }
    pre code .hljs-built_in { color: #66D9EF; }
    """

    static let previewPalette = SyntaxThemePreviewPalette(
        blockTextHex: "#F8F8F2",
        blockBackgroundHex: "#1E1F1C",
        blockBorderHex: "#3A3C33",
        commentHex: "#75715E",
        keywordHex: "#F92672",
        stringHex: "#E6DB74",
        numberHex: "#AE81FF",
        titleHex: "#A6E22E",
        builtInHex: "#66D9EF"
    )
}
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/MonokaiTheme.swift
git commit -m "Add Monokai theme definition with syntax highlighting"
```

---

### Task 8: Wire themes into ThemeDefinition mapping

**Files:**
- Modify: `minimark/Models/ThemeDefinition.swift`

- [ ] **Step 1: Add cases to the `themeDefinition` switch**

Add after the `case .gameBoy:` line (line 41), before the closing `}`:

```swift
        case .gruvboxDark:
            return GruvboxDarkTheme.definition
        case .gruvboxLight:
            return GruvboxLightTheme.definition
        case .dracula:
            return DraculaTheme.definition
        case .monokai:
            return MonokaiTheme.definition
```

- [ ] **Step 2: Commit**

```bash
git add minimark/Models/ThemeDefinition.swift
git commit -m "Wire Gruvbox Dark/Light, Dracula, Monokai into ThemeDefinition mapping"
```

---

### Task 9: Add tests for new themes

**Files:**
- Modify: `minimarkTests/Rendering/ThemeDefinitionTests.swift`

- [ ] **Step 1: Add Gruvbox Dark tests**

Add after the Game Boy section (after line 339), before the "Theme Color Scheme Consistency" section:

```swift
    // MARK: - Gruvbox Dark Theme

    func testGruvboxDarkThemeDefinition() {
        let definition = ReaderThemeKind.gruvboxDark.themeDefinition
        XCTAssertEqual(definition.displayName, "Gruvbox Dark")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testGruvboxDarkColors() {
        let definition = ReaderThemeKind.gruvboxDark.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#282828")
        XCTAssertEqual(definition.colors.foregroundHex, "#EBDBB2")
        XCTAssertEqual(definition.colors.linkHex, "#FE8019")
        XCTAssertEqual(definition.colors.h1Hex, "#FB4934")
        XCTAssertEqual(definition.colors.h2Hex, "#B8BB26")
        XCTAssertEqual(definition.colors.h3Hex, "#83A598")
    }

    func testGruvboxDarkSyntaxCSSCoversAllTokenTypes() {
        let css = ReaderThemeKind.gruvboxDark.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    func testGruvboxDarkUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.gruvboxDark.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: #FB4934"), "Should contain Gruvbox Dark keyword color")
        XCTAssertFalse(css.contains("#D73A49"), "Should not contain GitHub keyword color")
    }

    func testGruvboxDarkCSSContainsHeaderVariables() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.gruvboxDark.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("--reader-h1: #FB4934"))
        XCTAssertTrue(css.contains("--reader-h2: #B8BB26"))
        XCTAssertTrue(css.contains("--reader-h3: #83A598"))
    }

    // MARK: - Gruvbox Light Theme

    func testGruvboxLightThemeDefinition() {
        let definition = ReaderThemeKind.gruvboxLight.themeDefinition
        XCTAssertEqual(definition.displayName, "Gruvbox Light")
        XCTAssertFalse(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testGruvboxLightColors() {
        let definition = ReaderThemeKind.gruvboxLight.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#FBF1C7")
        XCTAssertEqual(definition.colors.foregroundHex, "#3C3836")
        XCTAssertEqual(definition.colors.linkHex, "#076678")
        XCTAssertEqual(definition.colors.h1Hex, "#9D0006")
        XCTAssertEqual(definition.colors.h2Hex, "#79740E")
        XCTAssertEqual(definition.colors.h3Hex, "#076678")
    }

    func testGruvboxLightSyntaxCSSCoversAllTokenTypes() {
        let css = ReaderThemeKind.gruvboxLight.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    func testGruvboxLightUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.gruvboxLight.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: #9D0006"), "Should contain Gruvbox Light keyword color")
        XCTAssertFalse(css.contains("#D73A49"), "Should not contain GitHub keyword color")
    }

    // MARK: - Dracula Theme

    func testDraculaThemeDefinition() {
        let definition = ReaderThemeKind.dracula.themeDefinition
        XCTAssertEqual(definition.displayName, "Dracula")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testDraculaColors() {
        let definition = ReaderThemeKind.dracula.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#282A36")
        XCTAssertEqual(definition.colors.foregroundHex, "#F8F8F2")
        XCTAssertEqual(definition.colors.linkHex, "#8BE9FD")
        XCTAssertEqual(definition.colors.h1Hex, "#FF79C6")
        XCTAssertEqual(definition.colors.h2Hex, "#50FA7B")
        XCTAssertEqual(definition.colors.h3Hex, "#8BE9FD")
    }

    func testDraculaSyntaxCSSCoversAllTokenTypes() {
        let css = ReaderThemeKind.dracula.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    func testDraculaUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.dracula.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: #FF79C6"), "Should contain Dracula keyword color")
        XCTAssertFalse(css.contains("#F92672"), "Should not contain Monokai keyword color")
    }

    func testDraculaCSSContainsHeaderVariables() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.dracula.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("--reader-h1: #FF79C6"))
        XCTAssertTrue(css.contains("--reader-h2: #50FA7B"))
        XCTAssertTrue(css.contains("--reader-h3: #8BE9FD"))
    }

    // MARK: - Monokai Theme

    func testMonokaiThemeDefinition() {
        let definition = ReaderThemeKind.monokai.themeDefinition
        XCTAssertEqual(definition.displayName, "Monokai")
        XCTAssertTrue(definition.kind.isDark)
        XCTAssertNil(definition.customCSS)
        XCTAssertNil(definition.customJavaScript)
        XCTAssertTrue(definition.providesSyntaxHighlighting)
        XCTAssertNotNil(definition.syntaxCSS)
        XCTAssertNotNil(definition.syntaxPreviewPalette)
    }

    func testMonokaiColors() {
        let definition = ReaderThemeKind.monokai.themeDefinition
        XCTAssertEqual(definition.colors.backgroundHex, "#272822")
        XCTAssertEqual(definition.colors.foregroundHex, "#F8F8F2")
        XCTAssertEqual(definition.colors.linkHex, "#A6E22E")
        XCTAssertEqual(definition.colors.h1Hex, "#F92672")
        XCTAssertEqual(definition.colors.h2Hex, "#A6E22E")
        XCTAssertEqual(definition.colors.h3Hex, "#66D9EF")
    }

    func testMonokaiSyntaxCSSCoversAllTokenTypes() {
        let css = ReaderThemeKind.monokai.themeDefinition.syntaxCSS!
        XCTAssertTrue(css.contains(".hljs-comment"))
        XCTAssertTrue(css.contains(".hljs-keyword"))
        XCTAssertTrue(css.contains(".hljs-string"))
        XCTAssertTrue(css.contains(".hljs-number"))
        XCTAssertTrue(css.contains(".hljs-title"))
        XCTAssertTrue(css.contains(".hljs-built_in"))
    }

    func testMonokaiUsesSyntaxCSSInsteadOfSyntaxTheme() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.monokai.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: #F92672"), "Should contain Monokai keyword color")
        XCTAssertFalse(css.contains("#D73A49"), "Should not contain GitHub keyword color")
    }

    func testMonokaiCSSContainsHeaderVariables() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.monokai.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .github, baseFontSize: 16)
        XCTAssertTrue(css.contains("--reader-h1: #F92672"))
        XCTAssertTrue(css.contains("--reader-h2: #A6E22E"))
        XCTAssertTrue(css.contains("--reader-h3: #66D9EF"))
    }

    // MARK: - Header Color Fallback

    func testSimpleThemesDoNotEmitHeaderVariables() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertFalse(css.contains("--reader-h1:"), "Simple themes should not emit h1 variable")
        XCTAssertFalse(css.contains("--reader-h2:"), "Simple themes should not emit h2 variable")
        XCTAssertFalse(css.contains("--reader-h3:"), "Simple themes should not emit h3 variable")
    }

    func testSimpleThemesHeaderColorsFallBackToForeground() {
        let factory = ReaderCSSFactory()
        let theme = ReaderThemeKind.blackOnWhite.themeDefinition
        let css = factory.makeCSS(theme: theme, syntaxTheme: .monokai, baseFontSize: 16)
        XCTAssertTrue(css.contains("color: var(--reader-h1, var(--reader-fg))"), "h1 should fall back to foreground")
        XCTAssertTrue(css.contains("color: var(--reader-h2, var(--reader-fg))"), "h2 should fall back to foreground")
        XCTAssertTrue(css.contains("color: var(--reader-h3, var(--reader-fg))"), "h3 should fall back to foreground")
    }
```

- [ ] **Step 2: Commit**

```bash
git add minimarkTests/Rendering/ThemeDefinitionTests.swift
git commit -m "Add tests for Gruvbox Dark/Light, Dracula, Monokai themes and header color system"
```

---

### Task 10: Add new theme files to Xcode project and build

**Files:**
- Modify: `minimark.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add new Swift files to the Xcode project**

The 4 new files need to be added to the Xcode project's build sources:
- `minimark/Models/GruvboxDarkTheme.swift`
- `minimark/Models/GruvboxLightTheme.swift`
- `minimark/Models/DraculaTheme.swift`
- `minimark/Models/MonokaiTheme.swift`

Use `ruby` or manual editing of `project.pbxproj` to add PBXFileReference and PBXBuildFile entries, following the pattern of existing theme files like `GameBoyTheme.swift`. Alternatively, if the project uses a folder reference for the Models directory, the files may be picked up automatically.

- [ ] **Step 2: Build the project**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark.xcodeproj/project.pbxproj
git commit -m "Add new theme files to Xcode project"
```

---

### Task 11: Run full test suite and verify

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests`
Expected: All tests pass, including new theme tests and existing tests (no regressions).

- [ ] **Step 2: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "Fix test failures from new theme integration"
```
