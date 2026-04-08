# Sidebar Group Drag-and-Drop Reorder — Status Report

**Branch:** `feature/197-manual-sidebar-reorder`
**Date:** 2026-04-08
**Issue:** #197

## Summary

Manual drag-and-drop reordering of sidebar groups is **partially working**. The core data flow (model, persistence, post-processing) is complete and fully tested. The drag gesture recognition and reorder execution work correctly. Three UX issues remain open, and one of the attempted fixes introduced a regression.

## What Works

### Backend (complete, all tests pass)

- `ReaderSidebarSortMode.manualOrder` case added, hidden from sort menu via custom `allCases`
- `SidebarGroupStateController.manualGroupOrder: [String]?` and `moveGroup(from:to:)` — sets manual order, switches sort mode
- Post-processing overlay in `recomputeGrouping()` — applies manual order only when `sortMode == .manualOrder`, preserves pinned group float-to-top, clears manual order when switching to algorithmic sort
- Persistence via `ReaderFavoriteWorkspaceState` (backward-compatible Codable), `WorkspaceStateSnapshot`, `applyWorkspaceState`, save-favorite flow
- **4 unit tests** in `SidebarGroupStateControllerTests` — all pass
- **1 Codable round-trip test** in `ReaderFavoriteWorkspaceStateTests` — passes
- **672 total unit tests pass**, Release build succeeds

### UI (partially working)

- Drag gesture is recognized (via `.simultaneousGesture` with `DragGesture`)
- Reorder executes correctly — `moveGroup(from:to:)` fires, grouping updates
- Sort mode switches to "Manual" after drag
- Drop indicator renders between groups
- **UI test `testGroupedSidebarDragAndDropReordersGroups` passes** (with the working version — see below)

### Bug fix: pre-existing UI test infrastructure

- `applyUITestLaunchConfigurationIfNeeded()` in `ReaderWindowRootView.swift` had a bug where `hasAppliedUITestLaunchConfiguration` was set to `true` when the resolved action was `.none` (host window not yet available). This prevented the grouped sidebar test flow from ever executing. Removed the premature flag-set.

## Open Issues

### 1. Drop target calculation is inaccurate

**Problem:** The original `targetIndexFromY()` uses a fixed estimated section height of 36pt to convert global Y coordinate to a group index. Real section heights vary (expanded vs collapsed, number of documents), so the drop indicator appears at the wrong position — often several groups lower than where the cursor actually is.

**Attempted fix (currently broken):** Replaced with `targetIndexFromGlobalY()` that uses actual group header frames tracked via `GeometryReader` + `PreferenceKey`. This caused an infinite layout loop — when the dragged section is offset via `.offset(dragTranslation)`, the `GeometryReader` inside it reports a new frame, which triggers `onPreferenceChange`, which updates `@State groupHeaderGlobalFrames`, which causes a re-render, creating a feedback loop. Guarding with `if draggedGroupID == nil` did not help because the preference system still processes the updates.

**State in working tree:** The `@State groupHeaderGlobalFrames` declaration was accidentally removed during iteration, but references to it remain in `targetIndexFromGlobalY()` and `fallbackTargetIndex()`. The code **does not compile** in the current working tree state.

**Recommended approach:** Instead of tracking frames reactively, compute the target index from the drag gesture's start position and translation relative to the known group ordering. Since we know the group indices and can read the initial frame of the dragged group at drag start, we can estimate the target based on how far the cursor has moved relative to the other groups' known initial positions. Alternatively, use a separate non-reactive reference (e.g., a `Box<[String: CGRect]>` class) to store frames without triggering SwiftUI re-renders.

### 2. Dragged group does not visually follow the cursor

**Problem:** The dragged group becomes semi-transparent (0.4 opacity) but stays in place. The user expects the group to move with the cursor during the drag, like a standard drag-and-drop preview.

**Attempted fix:** Added `@State dragTranslation: CGSize` and `.offset(dragTranslation)` on the dragged section. This works visually but interacts badly with the GeometryReader frame tracking (see issue 1 above).

**State in working tree:** The `dragTranslation` state and `.offset()` modifier are in the diff but cannot be tested due to the broken frame tracking code.

**Recommended approach:** This should work once the frame tracking approach is resolved. The `.offset()` + `.opacity(0.4)` combination creates a reasonable drag preview. Consider using a higher opacity (e.g., 0.7) and adding a subtle shadow to the dragged section for better visibility.

### 3. Drop indicator is too subtle

**Problem:** The original drop indicator was a 2pt semi-transparent rectangle. Even after improving it to a 3pt capsule with full accent color, it may still be hard to notice during a drag.

**State:** The improved `SidebarGroupDropIndicator` (Capsule, full accent color, 3pt) is in the working tree diff. This is a reasonable improvement but hasn't been visually tested by the user yet.

**Consider:** Adding padding around the indicator to create a visible gap in the list, or using a more prominent visual treatment (e.g., a line with a circle at the leading edge).

## File Change Summary

### Modified source files (from branch commits + working tree)

| File | Changes |
|------|---------|
| `minimark/Models/ReaderSidebarSortMode.swift` | Added `.manualOrder` case, custom `allCases`, display names |
| `minimark/Models/ReaderSidebarGrouping.swift` | Added `.manualOrder` case to `sorted()` switch |
| `minimark/Stores/SidebarGroupStateController.swift` | `manualGroupOrder`, `moveGroup(from:to:)`, `applyManualOrder()`, sort mode didSet, snapshot/apply |
| `minimark/Models/ReaderFavoriteWorkspaceState.swift` | `manualGroupOrder` field, custom CodingKeys/init |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Drag gesture, drop indicator, drag handlers, offset (partially broken) |
| `minimark/Views/ReaderWindowRootView.swift` | Persistence wiring, UI test config fix |
| `minimark/Views/Window/Flow/ReaderWindowRootView+SidebarCommandFlow.swift` | Save-favorite includes `manualGroupOrder` |
| `minimarkUITests/minimarkUITests.swift` | New `testGroupedSidebarDragAndDropReordersGroups` test |

### Modified test files

| File | Changes |
|------|---------|
| `minimarkTests/Sidebar/SidebarGroupStateControllerTests.swift` | 4 new tests for manual order |
| `minimarkTests/Core/ReaderFavoriteWorkspaceStateTests.swift` | Codable round-trip test |

## Key Discoveries

1. **`Button` consumes gestures.** The original `AnimatedSidebarGroupSection` wrapped the header in a `Button`, which consumed the mouse-down event and prevented `.onDrag` from activating. Fixed by switching to `onTapGesture` + `.simultaneousGesture(DragGesture)`.
2. **`.gesture()` vs `.simultaneousGesture()`.** A child `onTapGesture` has higher priority than a parent `.gesture()`. Must use `.simultaneousGesture()` to allow both tap and drag.
3. **`draggedGroupID` was never set.** The original `handleDragUpdate` only updated `dropTargetIndex` but never initialized `draggedGroupID`, making the entire drag visual feedback dead.
4. **UI test grouped sidebar flow was broken.** `applyUITestLaunchConfigurationIfNeeded()` permanently set the applied flag when the host window wasn't available yet, preventing the test flow from ever executing.
5. **GeometryReader + PreferenceKey + offset = layout loop.** Using `GeometryReader` to track frames of views that are being offset during drag creates an infinite feedback loop in SwiftUI. This is a fundamental constraint that must be worked around.

## How to Get Back to a Working State

The last known working state is commit `5a226aa` (the previous commit on this branch). The working tree changes introduce the UX improvements but are currently in a broken state due to the GeometryReader feedback loop issue.

To restore to a working state while preserving the improvements that do work:

1. Keep: `draggedGroupID` initialization fix, `.simultaneousGesture` fix, `dragTranslation` tracking, drop indicator improvement
2. Revert: `GroupHeaderFramePreferenceKey`, `GroupHeaderFrameReader`, `onPreferenceChange`, `targetIndexFromGlobalY`, `fallbackTargetIndex`
3. Restore: A fixed-up version of `targetIndexFromY` that uses the drag start position + translation delta instead of absolute global Y coordinates, which avoids needing frame tracking entirely

## Recommended Next Steps

1. **Revert the GeometryReader approach** and instead compute the drop target from the drag gesture's translation delta. Since we know the index of the dragged group and how far the cursor has moved, we can determine the target index relative to the known group ordering without any frame tracking.
2. **Keep the drag offset** (`.offset(dragTranslation)`) for visual feedback — it works when not combined with GeometryReader.
3. **Tune the drop indicator** visually after the core mechanics work correctly.
4. **Update the UI test** to verify the improved behavior.
