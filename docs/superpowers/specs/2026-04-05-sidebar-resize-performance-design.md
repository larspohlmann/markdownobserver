# Sidebar Resize Performance Refactoring

**Issue:** [#155](https://github.com/larspohlmann/markdownobserver/issues/155)
**Related:** [#71](https://github.com/larspohlmann/markdownobserver/issues/71) (fixed sidebar width during window resize), [#149](https://github.com/larspohlmann/markdownobserver/pull/149) (scan delay / sidebar re-render fix)

## Problem

Resizing the sidebar is sluggish when a folder with many entries is open. Multiple compounding causes:

1. **TimelineView with 20ms refresh on every row** — Each `ReaderSidebarDocumentRow` has `TimelineView(.periodic(from: .now, by: 20))` for relative timestamps. With 50 files open, that's 2,500 view updates per second — all firing during resize.

2. **Every row observes full ReaderStore** — Each row takes `@ObservedObject var readerStore: ReaderStore`, subscribing to ALL published properties (HTML content, file metadata, appearance, folder watch state). Any ReaderStore change invalidates the row.

3. **#71's width constraint mechanism** — The `isDraggingDivider` @State toggles `maxWidth` between a fixed value and `.infinity`. Each toggle invalidates the entire sidebar column body. A `GeometryReader` + `SidebarWidthPreferenceKey` reads width continuously during drag, creating a feedback loop with the `sidebarWidth` binding.

4. **Scan progress invalidates sidebar column** — `contentScanProgress` updates on `ReaderSidebarDocumentController` re-render the footer, which lives inside the same column body as the List. Every progress tick re-evaluates the full sidebar.

## Design

Four changes, ordered by impact.

### 1. Replace HSplitView with custom NSSplitViewController wrapper

Replace `HSplitView` + `SidebarDividerPositionSetter` + `GeometryReader` + `SidebarWidthPreferenceKey` + `isDraggingDivider` with a single `SidebarSplitView` — an `NSViewControllerRepresentable` wrapping `NSSplitViewController`.

Inspired by the Clearance app's `OutlineSplitView`, but adapted for a **user-resizable** sidebar (not a fixed-width inspector):

- Use `NSSplitViewItem(viewController:)` (not `inspectorWithViewController:`) since the sidebar must be drag-resizable
- Set `holdingPriority = .defaultHigh` so the sidebar resists proportional redistribution during window resize — this alone solves the original #71 problem
- Track divider drag via mouse event monitors inside the controller; report the final sidebar width back to SwiftUI only on drag end — no GeometryReader, no preference key, no `isDraggingDivider` exposed to the view layer
- Support left/right placement via NSSplitViewItem ordering
- Width is written to the SwiftUI binding only on drag end (not every pixel)

```swift
struct SidebarSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebarWidth: CGFloat
    let sidebarPlacement: SidebarPlacement
    let onSidebarWidthChanged: (CGFloat) -> Void
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail
}
```

The backing `SidebarSplitViewController` (NSSplitViewController subclass):
- Creates two `NSHostingController`s for sidebar and detail content
- Configures `NSSplitViewItem` holding priorities to resist window-resize redistribution
- Sets `minimumThickness` on the sidebar item (220pt minimum)
- Tracks mouse-down/up on the divider (via `NSEvent` local monitors, minimal version of the current approach) to detect drag start/end; reports final width to SwiftUI only on drag end via the `onSidebarWidthChanged` callback
- Handles placement changes by reordering split view items

**Eliminates:** `SidebarDividerPositionSetter.swift` (deleted), `SidebarWidthPreferenceKey`, `isDraggingDivider` @State, GeometryReader in sidebar, conditional `maxWidth` frame modifier.

### 2. Lightweight row view-model (SidebarRowState)

Replace `@ObservedObject var readerStore: ReaderStore` per row with a value-type struct:

```swift
struct SidebarRowState: Equatable, Identifiable {
    let id: UUID
    let title: String
    let lastModified: Date?
    let isFileMissing: Bool
    let indicatorState: ReaderDocumentIndicatorState
}
```

`ReaderSidebarDocumentController` derives `[SidebarRowState]` from the underlying ReaderStores. Because the struct is `Equatable`, SwiftUI skips re-rendering rows whose state hasn't actually changed — even if the underlying ReaderStore emitted an unrelated update (HTML re-render, appearance change, etc.).

The row view becomes a pure function of `SidebarRowState` with no `@ObservedObject`. It receives `currentDate: Date` from the parent TimelineView for relative time formatting.

### 3. Single 5s TimelineView at list level

Replace per-row `TimelineView(.periodic(from: .now, by: 20))` with a single `TimelineView(.periodic(from: .now, by: 5))` wrapping the entire List.

Each row receives `context.date` and formats its own `lastModified` against it:
- Documents < 1 minute old show seconds-level precision ("10s ago", "45s ago") — visibly updates every 5s
- Documents >= 1 minute old show minute-level precision ("3 min ago") — text doesn't change between 5s ticks

With lightweight `SidebarRowState` rows (no @ObservedObject, no complex subviews), evaluating 50 row bodies every 5s is negligible. This reduces update frequency from 2,500/s to 10/s (50 rows × 0.2 ticks/s), and most rows produce identical output so SwiftUI skips actual rendering.

### 4. Isolate scan progress as overlay

Extract the scan progress footer from the sidebar column body into a separate overlay:

```swift
ZStack(alignment: .bottom) {
    sidebarColumn       // List + toolbar — only invalidated by document changes
    SidebarScanProgressView(controller: controller)
}
```

`SidebarScanProgressView` is its own view struct with its own `@ObservedObject var controller`. When `contentScanProgress` changes, only this small overlay re-renders. The List underneath is untouched.

This separates two update cadences: document list changes (rare) vs. scan progress ticks (frequent during scan).

## Files Affected

| Action | File |
|--------|------|
| New | `minimark/Views/Window/SidebarSplitView.swift` |
| New | `minimark/Views/SidebarScanProgressView.swift` |
| Modified | `minimark/Views/ReaderSidebarWorkspaceView.swift` — remove HSplitView, GeometryReader, isDraggingDivider, SidebarWidthPreferenceKey; use SidebarSplitView; wrap List in single TimelineView |
| Modified | `minimark/Views/ReaderSidebarWorkspaceView.swift` (private `ReaderSidebarDocumentRow`) — accept SidebarRowState + currentDate instead of ReaderStore |
| Modified | `minimark/Views/ReaderWindowRootView.swift` — remove sidebarWidth onChange that fires every pixel; adapt to SidebarSplitView callback |
| Modified | `minimark/Stores/ReaderSidebarDocumentController.swift` — add SidebarRowState derivation |
| Deleted | `minimark/Views/Window/SidebarDividerPositionSetter.swift` |

## Behavioral Preservation

- Sidebar width persists to favorites (via delegate callback instead of preference key)
- Left/right sidebar placement still works (item ordering in NSSplitViewController)
- Sidebar resists proportional resizing during window resize (holdingPriority, solving #71)
- All sort modes, grouping, disclosure groups, context menus unchanged
- Relative timestamps still individual per document, updating every 5s
- Scan progress bar still visible during folder scan

## Out of Scope

No changes to ReaderStore internals, detail view, folder watch logic, or document opening flows.
