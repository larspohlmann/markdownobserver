# Custom Checkbox Styling for Task Lists

**Issue:** [#55](https://github.com/larspohlmann/markdownobserver/issues/55)
**Date:** 2026-04-01

## Problem

Default browser checkboxes in rendered markdown task lists are small and visually understated. Checked vs. unchecked states lack visual clarity when scanning documents.

## Design: Rounded Fill Checkbox

Replace the native OS checkbox with a custom-drawn CSS checkbox using `appearance: none` and pseudo-elements on the existing `<input type="checkbox">` element.

### Visual Spec

| State | Appearance |
|-------|-----------|
| **Unchecked** | Rounded box (4px border-radius), 1.5px border in `--reader-border`, empty interior matching page background |
| **Checked** | Box filled with `--reader-link` color, border matches fill, white SVG checkmark rendered via inline `background-image` data URI |
| **Checked text** | Dimmed to 55% opacity, no strikethrough |

### Sizing and Alignment

- Box: `1.15em` square — scales with the base font size
- Margin: `0.25em 0.55em 0 0` (preserving current spacing)
- Vertical alignment: `margin-top: 0.15em` to align with first line of text

### Theme Integration

Uses two existing CSS custom properties — no new variables needed:

- `--reader-border` for the unchecked box border
- `--reader-link` for the checked fill color

Works across all four themes:
- White (`#005FCC` fill, `#D9D9D9` border)
- Black (`#7DB4FF` fill, `#303030` border)
- Light Gray (`#004F9A` fill, `#B8B8B8` border)
- Dark Gray (`#8AB9FF` fill, `#5A5A5A` border)

### CSS Implementation

The checkmark is rendered as an inline SVG data URI in `background-image` on the checked state. This keeps it CSS-only — no additional assets or DOM changes.

```css
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
  position: relative;
}

.markdown-body .task-list-item-checkbox:checked {
  background-color: var(--reader-link);
  border-color: var(--reader-link);
  background-image: url("data:image/svg+xml,...checkmark...");
  background-size: 0.7em 0.7em;
  background-position: center;
  background-repeat: no-repeat;
}
```

For checked text dimming: the sanitizer strips `<label>` tags, so checked item text is a bare text node inside the `<li>`. CSS sibling selectors can't target bare text nodes, so we use `:has()` on the parent `<li>` and restore full opacity on the checkbox itself:

```css
.markdown-body .task-list-item:has(.task-list-item-checkbox:checked) {
  opacity: 0.55;
}
.markdown-body .task-list-item:has(.task-list-item-checkbox:checked) .task-list-item-checkbox {
  opacity: 1;
}
```

### Scope

**Single file change:** `minimark/Support/ReaderCSSFactory.swift` — replace the existing `.task-list-item-checkbox` CSS block (lines ~447–454) with the new rules.

### Constraints

- CSS-only — no JavaScript, no DOM changes, no new assets
- `pointer-events: none` preserved — checkboxes are read-only
- No new CSS variables needed
- The `accent-color` property is removed (replaced by explicit fill)
- WKWebView on macOS supports `appearance: none`, `:checked`, `:has()`, and SVG data URIs

### Testing

- Add a unit test in `minimarkTests/Rendering/` that verifies the generated CSS contains the new checkbox rules
- Manual verification across all four themes with a markdown file containing task lists with mixed checked/unchecked items
