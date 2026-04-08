# Custom Checkbox Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace default browser checkboxes in markdown task lists with custom-drawn rounded fill checkboxes that are visually distinct across all four themes.

**Architecture:** CSS-only change in `ReaderCSSFactory.makeCSS`. Uses `appearance: none` to suppress the native checkbox, then draws a custom box via border/background properties and renders the checkmark as an inline SVG data URI. Checked item text is dimmed via `:has()` selector on the parent `<li>`.

**Tech Stack:** Swift (string literal CSS), CSS3, SVG data URI

---

## File Map

- **Modify:** `minimark/Support/ReaderCSSFactory.swift:447-454` — replace existing `.task-list-item-checkbox` CSS block with custom checkbox rules
- **Create:** `minimarkTests/Rendering/CheckboxCSSTests.swift` — unit tests verifying generated CSS contains the new checkbox rules

---

### Task 1: Write failing tests for checkbox CSS

**Files:**
- Create: `minimarkTests/Rendering/CheckboxCSSTests.swift`

- [ ] **Step 1: Create the test file**

```swift
//
//  CheckboxCSSTests.swift
//  minimarkTests
//

import Testing
@testable import minimark

@Suite
struct CheckboxCSSTests {
    private let factory = ReaderCSSFactory()
    private let css = ReaderCSSFactory().makeCSS(
        theme: .default,
        syntaxTheme: .default,
        baseFontSize: 16.0
    )

    @Test
    func checkboxUsesAppearanceNone() {
        #expect(css.contains("appearance: none"))
    }

    @Test
    func checkboxHasRoundedBorder() {
        #expect(css.contains("border-radius: 4px"))
        #expect(css.contains("border: 1.5px solid var(--reader-border)"))
    }

    @Test
    func checkedCheckboxFillsWithLinkColor() {
        #expect(css.contains("background-color: var(--reader-link)"))
        #expect(css.contains("border-color: var(--reader-link)"))
    }

    @Test
    func checkedCheckboxHasSVGCheckmark() {
        #expect(css.contains("background-image: url(\"data:image/svg+xml"))
    }

    @Test
    func checkedItemTextIsDimmed() {
        #expect(css.contains(".task-list-item:has(.task-list-item-checkbox:checked)"))
        #expect(css.contains("opacity: 0.55"))
    }

    @Test
    func checkboxIsNotInteractive() {
        #expect(css.contains("pointer-events: none"))
    }

    @Test
    func noAccentColorRemains() {
        #expect(!css.contains("accent-color"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/CheckboxCSSTests 2>&1 | tail -20`

Expected: Multiple failures — `checkboxUsesAppearanceNone`, `checkboxHasRoundedBorder`, `checkedCheckboxFillsWithLinkColor`, `checkedCheckboxHasSVGCheckmark`, `checkedItemTextIsDimmed` all fail. `checkboxIsNotInteractive` passes (already in CSS). `noAccentColorRemains` fails (accent-color is still present).

- [ ] **Step 3: Commit**

```bash
git add minimarkTests/Rendering/CheckboxCSSTests.swift
git commit -m "test(#55): add failing tests for custom checkbox CSS"
```

---

### Task 2: Replace checkbox CSS in ReaderCSSFactory

**Files:**
- Modify: `minimark/Support/ReaderCSSFactory.swift:447-454`

- [ ] **Step 1: Replace the existing checkbox CSS block**

In `minimark/Support/ReaderCSSFactory.swift`, replace lines 447–454 (the `.task-list-item-checkbox` block):

```swift
// OLD (lines 447-454):
        .markdown-body .task-list-item-checkbox {
          margin: 0.25em 0.55em 0 0;
          inline-size: 1em;
          block-size: 1em;
          vertical-align: top;
          accent-color: var(--reader-link);
          pointer-events: none;
        }
```

Replace with:

```swift
// NEW:
        .markdown-body .task-list-item-checkbox {
          -webkit-appearance: none;
          appearance: none;
          margin: 0.25em 0.55em 0 0;
          inline-size: 1.15em;
          block-size: 1.15em;
          vertical-align: top;
          border: 1.5px solid var(--reader-border);
          border-radius: 4px;
          background: transparent;
          pointer-events: none;
        }

        .markdown-body .task-list-item-checkbox:checked {
          background-color: var(--reader-link);
          border-color: var(--reader-link);
          background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 12 12' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M2.5 6.5L5 9L9.5 3.5' stroke='white' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
          background-size: 0.7em 0.7em;
          background-position: center;
          background-repeat: no-repeat;
        }

        .markdown-body .task-list-item:has(.task-list-item-checkbox:checked) {
          opacity: 0.55;
        }

        .markdown-body .task-list-item:has(.task-list-item-checkbox:checked) .task-list-item-checkbox {
          opacity: 1;
        }
```

- [ ] **Step 2: Run the tests to verify they pass**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/CheckboxCSSTests 2>&1 | tail -20`

Expected: All 7 tests pass.

- [ ] **Step 3: Run the full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -20`

Expected: All tests pass — no regressions.

- [ ] **Step 4: Commit**

```bash
git add minimark/Support/ReaderCSSFactory.swift
git commit -m "feat(#55): replace native checkbox with custom rounded fill design"
```

---

### Task 3: Manual visual verification

- [ ] **Step 1: Create a test markdown file**

Create a temporary markdown file with this content for manual testing:

```markdown
## Task List Test

- [x] Completed item one
- [x] Another completed item
- [ ] Pending item
- [ ] Another pending item
- [x] Third completed with `inline code`

### Nested list

- [ ] Parent task
  - [x] Sub-task done
  - [ ] Sub-task pending
```

- [ ] **Step 2: Verify across all four themes**

Build and run the app. Open the test markdown file. Switch through all four reader themes and verify:
- Unchecked boxes show a rounded bordered box matching the theme
- Checked boxes fill with the theme's link color and show a white checkmark
- Checked item text is dimmed but readable (no strikethrough)
- The checkbox does not respond to clicks (pointer-events: none)
- Nested task lists render correctly

- [ ] **Step 3: Clean up**

Delete the temporary test markdown file.
