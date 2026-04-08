# Manual Drag-and-Drop Reordering of Sidebar Groups

## Summary

Allow users to manually reorder sidebar groups (folder sections) via drag-and-drop. When a manual reorder occurs, the group sort mode switches to a new `.manualOrder` mode. The custom order persists for the session and is saved/restored with favorites.

## Data Model Changes

### ReaderSidebarSortMode

Add `.manualOrder` case to `ReaderSidebarSortMode`. Override `CaseIterable` conformance to explicitly list only the 5 existing algorithmic cases (the sort dropdown menu continues showing only these). Add `displayName` = "Manual" and `footerLabel` = "Manual" for the new case.

### SidebarGroupStateController

Add `manualGroupOrder: [String]?` property (nil means no manual order established). Add `func moveGroup(from sourceIndex: Int, to destinationIndex: Int)` that:
1. Computes the new ordered list of group IDs by moving the group at `sourceIndex` to `destinationIndex`
2. Sets `manualGroupOrder` to the new order
3. Switches `sortMode` to `.manualOrder`

### ReaderFavoriteWorkspaceState

Add `manualGroupOrder: [String]?` as an optional Codable field. Defaults to nil (backward-compatible with existing saved favorites).

## Sorting Logic

Manual ordering is a **post-processing overlay** applied in `SidebarGroupStateController.recomputeGrouping()` after the existing grouping computation:

- If `sortMode == .manualOrder` and `manualGroupOrder` is non-nil, reorder the groups in the `.grouped` result to match `manualGroupOrder`
- Groups not present in `manualGroupOrder` (newly appeared folders) are appended at the end in their algorithmic sort order
- Pinned groups continue to float to the top, respecting their relative manual order within the pinned/unpinned partitions
- `ReaderSidebarGrouping.group()` itself does not change

## Drag-and-Drop UI

Custom drag-and-drop on group section headers within the existing `ScrollView + LazyVStack`:

- Each `AnimatedSidebarGroupSection` gets `onDrag` returning an `NSItemProvider` with the group ID
- `onDrop` handlers between/on sections extract the dragged group ID, compute the new order, and call `groupState.moveGroup(from:to:)`
- The drag handle is the group header area (`ReaderSidebarGroupHeader`)
- **Sliding animations**: When a group is dragged over a drop target, surrounding groups slide apart with smooth animation to create a gap. On drop, the group slides into its new position. Achieved by tracking drop target index in `@State` and conditionally adding animated spacers/padding.

## Sort Menu Behavior

- When `sortMode` is `.manualOrder`, the group sort menu displays "Manual" with the folder icon
- Selecting any algorithmic sort mode from the dropdown clears `manualGroupOrder` (sets to nil) and switches to that mode
- The manual mode is only activated via drag-reorder — it does not appear as a clickable option in the sort menu

## Favorites Persistence

- `SidebarGroupStateController.applyWorkspaceState()` restores `manualGroupOrder` from the saved state
- `SidebarGroupStateController.persistenceSnapshot` includes `manualGroupOrder`
- `SidebarGroupStateController.WorkspaceStateSnapshot` includes `manualGroupOrder`
- When a favorite is opened, the manual order is restored; when workspace state is snapshotted for saving, the current manual order is included

## Files to Modify

| File | Change |
|------|--------|
| `minimark/Models/ReaderSidebarSortMode.swift` | Add `.manualOrder` case, custom `CaseIterable` |
| `minimark/Stores/SidebarGroupStateController.swift` | Add `manualGroupOrder`, `moveGroup(from:to:)`, post-processing in `recomputeGrouping()`, persistence |
| `minimark/Models/ReaderFavoriteWorkspaceState.swift` | Add `manualGroupOrder` field |
| `minimark/Views/ReaderSidebarWorkspaceView.swift` | Drag-and-drop on `SidebarGroupListContent`, sliding animations |
| `minimarkTests/` | Tests for manual order post-processing, persistence, and favorites integration |
