# Overlay Inset Alignment and Scroll Landing — Design Spec

**Issue:** [#186](https://github.com/larspohlmann/markdownobserver/issues/186)
**Date:** 2026-04-07

## Summary

Unify top-offset behavior for reader overlays and scroll landing so all top controls move together across top-bar states, warning bars, and source-edit mode.

This design ensures:

- `DeletedFileWarningBar` and `ImageAccessWarningBar` remain directly below the top bar.
- `ChangeNavigationPill`, `WatchPill`, and `ContentUtilityRail` shift down together whenever source-edit or warning bars are visible.
- `WatchPill` and `ChangeNavigationPill` top borders align with `ContentUtilityRail`'s top border.
- changed-region and TOC scroll targets land below the watch/navigation pills with a consistent margin.

## Goals

1. Eliminate duplicated top-inset math across SwiftUI overlays and WebView scroll logic.
2. Keep visual alignment stable across all combinations of:
   - top bar only,
   - top bar + source-edit bar,
   - top bar + deleted warning,
   - top bar + image-access warning.
3. Use a shared metric set so future top-offset changes happen in one place.

## Non-Goals

- Redesigning overlay horizontal spacing.
- Changing warning bar copy or visual style.
- Changing changed-region detection logic.

## Design

### 1) Shared overlay metrics in `ContentView`

Introduce a small, centralized metric group for top-offset behavior (single source of truth):

- `overlayBaseGap`: default vertical spacing below bars.
- `leadingOverlayAlignmentAdjustment`: extra vertical adjustment so watch/prev-next border aligns with the right rail border.
- `overlayControlHeight`: top control capsule height (for scroll landing occlusion).
- `scrollLandingGap`: margin between bottom of top overlays and final scroll landing position.

`ContentView` computes:

- `topBarInset` (existing `ReaderTopBarMetrics`-based value).
- `statusBannerInset` (measured warning bar height; `0` when no warning bar).
- `overlayBaseInset = topBarInset + statusBannerInset + overlayBaseGap`.
- `overlayRailTopPadding` and `overlayLeadingPillTopPadding` derived from the same base + alignment adjustment.
- `scrollTargetTopInset = overlayLeadingPillTopPadding + overlayControlHeight + scrollLandingGap`.

This keeps movement synchronized while preserving the requested visual alignment.

### 2) Warning bar height is measured, not hardcoded

Warning bars can vary in height (text wrapping, accessibility sizes). Instead of constants, measure actual rendered warning bar height in `ContentView` using a lightweight preference-key pattern.

- When `DeletedFileWarningBar` or `ImageAccessWarningBar` is visible, write its rendered height into `statusBannerInset`.
- Otherwise, reset `statusBannerInset` to `0`.

This prevents drift from assumptions and keeps overlay placement correct under dynamic type and localization changes.

### 3) Overlay placement uses shared computed paddings

Apply shared paddings to all top overlays:

- `ContentUtilityRail` top padding uses `overlayRailTopPadding`.
- `ChangeNavigationPill` top padding uses `overlayLeadingPillTopPadding`.
- `WatchPill` top padding uses `overlayLeadingPillTopPadding`.

Horizontal paddings remain unchanged.

Result:

- Right rail keeps its current visual baseline.
- Watch/prev-next move slightly lower to align their top borders with the rail.
- All three move together when edit/warning bars appear.

### 4) Web scroll inset becomes host-driven and dynamic

Current runtime JS uses a static inset default (`56`). Replace this with a host-updated inset path:

- Add `overlayTopInset: CGFloat` input to `MarkdownWebView`.
- In `updateNSView`, push the latest inset to JS each update via a small setter call.
- In `markdownobserver-runtime.js`, keep a startup fallback value, but use mutable runtime inset for:
  - changed-region target scroll calculations,
  - changed-region "nearest marker" probe calculations,
  - heading scroll (`scrollToHeadingElement`) landing offset.

The pushed value is `scrollTargetTopInset` from `ContentView`, so landing remains below top overlays with consistent breathing room.

## File-Level Plan

| File | Change |
|------|--------|
| `minimark/ContentView.swift` | Add shared top-inset metric computation, warning-bar height measurement, unified overlay paddings, and pass dynamic inset into `MarkdownWebView`. |
| `minimark/Views/MarkdownWebView.swift` | Add dynamic overlay inset input and JS bridge setter call. Use this inset in TOC heading scroll script as well. |
| `minimark/App/Resources/markdownobserver-runtime.js` | Replace hardcoded inset behavior with mutable host-updated inset (with safe default), used by changed-region navigation math. |

## Error Handling and Safety

- JS setter is defensive: if runtime functions are not yet available, silently no-op.
- Runtime keeps a fallback inset value before first host update.
- Existing guards for missing DOM nodes/scroll containers remain unchanged.

## Testing Strategy

### Manual verification matrix

Verify visual alignment and scroll landing in each state:

1. top bar only,
2. top bar + source-edit bar,
3. top bar + deleted warning,
4. top bar + image-access warning.

For each state:

- Confirm watch/prev-next top border aligns with right rail top border.
- Confirm overlays do not overlap source-edit or warning bars.
- Trigger changed-region next/previous navigation and verify landing below top overlays.
- Trigger TOC heading navigation and verify landing below top overlays.

### Regression checks

- Build `minimark` debug scheme.
- Run `minimarkTests`.

## Acceptance Criteria

1. Warning bars remain directly attached below the top bar border.
2. Showing source-edit or warning bars shifts watch/prev-next/right rail down uniformly.
3. Watch/prev-next top borders align with right rail top border.
4. Changed-region and TOC jumps land below top overlays with consistent margin.
5. No regressions in build/test baseline.
