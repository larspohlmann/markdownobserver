# Sidebar Resize Performance Refactoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate sidebar resize sluggishness by replacing the fragile HSplitView/GeometryReader mechanism with a clean NSSplitViewController wrapper, removing per-row ReaderStore observation, consolidating TimelineView to a single 5s timer, and isolating scan progress rendering.

**Architecture:** Four independent changes that each reduce a specific source of unnecessary re-renders. The NSSplitViewController wrapper (inspired by Clearance's OutlineSplitView) gives direct AppKit control over column widths and holding priorities. SidebarRowState value types decouple row rendering from full ReaderStore observation. A single list-level TimelineView replaces 50+ per-row 20ms timers. Scan progress is rendered as an isolated overlay.

**Tech Stack:** SwiftUI, AppKit (NSSplitViewController, NSHostingController), Combine

**Spec:** `docs/superpowers/specs/2026-04-05-sidebar-resize-performance-design.md`

---

### Task 1: Create SidebarRowState model

**Files:**
- Create: `minimark/Models/SidebarRowState.swift`
- Test: `minimarkTests/Sidebar/SidebarRowStateTests.swift`

- [ ] **Step 1: Write the test for SidebarRowState derivation**

```swift
// minimarkTests/Sidebar/SidebarRowStateTests.swift
import Foundation
import Testing
@testable import minimark

@Suite
struct SidebarRowStateTests {
    @Test func derivesRowStateFromReaderStoreProperties() {
        let state = SidebarRowState(
            id: UUID(),
            title: "README.md",
            lastModified: Date(timeIntervalSince1970: 1000),
            isFileMissing: false,
            indicatorState: .none
        )

        #expect(state.title == "README.md")
        #expect(state.lastModified == Date(timeIntervalSince1970: 1000))
        #expect(state.isFileMissing == false)
        #expect(state.indicatorState == .none)
    }

    @Test func equatableSkipsIdenticalState() {
        let id = UUID()
        let date = Date()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: date, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: date, isFileMissing: false, indicatorState: .none)
        #expect(a == b)
    }

    @Test func equatableDetectsChangedTitle() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "B.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        #expect(a != b)
    }

    @Test func equatableDetectsChangedIndicator() {
        let id = UUID()
        let a = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .none)
        let b = SidebarRowState(id: id, title: "A.md", lastModified: nil, isFileMissing: false, indicatorState: .externalChange)
        #expect(a != b)
    }

    @Test func emptyDisplayNameBecomesUntitled() {
        let state = SidebarRowState(
            id: UUID(),
            title: "",
            lastModified: nil,
            isFileMissing: false,
            indicatorState: .none
        )
        #expect(state.title == "")
        // Note: the "Untitled" fallback is handled at derivation time (Task 2),
        // not in the struct itself.
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarRowStateTests 2>&1 | tail -5`
Expected: FAIL — `SidebarRowState` not found

- [ ] **Step 3: Create SidebarRowState struct**

```swift
// minimark/Models/SidebarRowState.swift
import Foundation

struct SidebarRowState: Equatable, Identifiable {
    let id: UUID
    let title: String
    let lastModified: Date?
    let isFileMissing: Bool
    let indicatorState: ReaderDocumentIndicatorState
}
```

Add the file to the Xcode project (same group as other model files in `minimark/Models/`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarRowStateTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Models/SidebarRowState.swift minimarkTests/Sidebar/SidebarRowStateTests.swift minimark.xcodeproj
git commit -m "feat: add SidebarRowState value type for lightweight sidebar rows"
```

---

### Task 2: Add SidebarRowState derivation to ReaderSidebarDocumentController

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift`
- Test: `minimarkTests/Sidebar/SidebarRowStateTests.swift` (extend)

The controller currently has `synchronizeDocumentChangeObservers()` (line 461) which blindly forwards every `readerStore.objectWillChange` to the controller's `objectWillChange`. This causes the entire sidebar to re-render on any store change — even HTML re-renders that don't affect the sidebar row.

Replace this with targeted `rowStates` updates that only trigger re-renders when row-visible data actually changes.

- [ ] **Step 1: Write test for row state derivation from controller**

Append to `minimarkTests/Sidebar/SidebarRowStateTests.swift`:

```swift
@Suite(.serialized)
struct SidebarRowStateDerivationTests {
    @Test @MainActor func controllerDerivesSidebarRowStateFromDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        #expect(harness.controller.rowStates.count == 1)

        let state = harness.controller.rowStates[0]
        #expect(state.id == harness.controller.documents[0].id)
        #expect(state.isFileMissing == false)
        #expect(state.indicatorState == .none)
    }

    @Test @MainActor func controllerUpdatesRowStatesWhenDocumentsChange() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let coordinator = FileOpenCoordinator(controller: harness.controller)
        coordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .manual
        ))

        #expect(harness.controller.rowStates.count == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarRowStateTests/SidebarRowStateDerivationTests 2>&1 | tail -5`
Expected: FAIL — `rowStates` property not found on controller

- [ ] **Step 3: Add rowStates property and derivation to controller**

In `minimark/Stores/ReaderSidebarDocumentController.swift`:

Add a new `@Published` property after line 22:
```swift
@Published private(set) var rowStates: [SidebarRowState] = []
```

Add a derivation method after the `makeDocument()` method (line 458):
```swift
private func deriveRowState(from document: Document) -> SidebarRowState {
    let store = document.readerStore
    return SidebarRowState(
        id: document.id,
        title: store.fileDisplayName.isEmpty ? "Untitled" : store.fileDisplayName,
        lastModified: store.fileLastModifiedAt,
        isFileMissing: store.isCurrentFileMissing,
        indicatorState: ReaderDocumentIndicatorState(
            hasUnacknowledgedExternalChange: store.hasUnacknowledgedExternalChange,
            isCurrentFileMissing: store.isCurrentFileMissing
        )
    )
}

private func rebuildAllRowStates() {
    rowStates = documents.map { deriveRowState(from: $0) }
}
```

Replace the current `synchronizeDocumentChangeObservers()` implementation (lines 461-473):

```swift
private func synchronizeDocumentChangeObservers() {
    let currentDocumentIDs = Set(documents.map(\.id))

    for documentID in documentChangeCancellables.keys where !currentDocumentIDs.contains(documentID) {
        documentChangeCancellables[documentID] = nil
    }

    for document in documents where documentChangeCancellables[document.id] == nil {
        documentChangeCancellables[document.id] = document.readerStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateRowStateIfNeeded(for: document.id)
            }
    }

    rebuildAllRowStates()
}

private func updateRowStateIfNeeded(for documentID: UUID) {
    guard let document = documents.first(where: { $0.id == documentID }) else { return }
    let newState = deriveRowState(from: document)
    guard let index = rowStates.firstIndex(where: { $0.id == documentID }) else { return }
    if rowStates[index] != newState {
        rowStates[index] = newState
    }
}
```

**Key difference from current code:** The old implementation called `self?.objectWillChange.send()` on every store change. The new implementation only updates `rowStates` (which triggers `objectWillChange` via `@Published`) when the derived row state actually changed. HTML re-renders, appearance changes, and other store mutations that don't affect the sidebar row are silently absorbed.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/SidebarRowStateTests/SidebarRowStateDerivationTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Run full existing sidebar tests to verify no regression**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests 2>&1 | tail -10`
Expected: All existing tests PASS

- [ ] **Step 6: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift minimarkTests/Sidebar/SidebarRowStateTests.swift
git commit -m "feat: add SidebarRowState derivation to controller, replace blind objectWillChange forwarding"
```

---

### Task 3: Create SidebarSplitView (NSSplitViewController wrapper)

**Files:**
- Create: `minimark/Views/Window/SidebarSplitView.swift`

This replaces `HSplitView` + `SidebarDividerPositionSetter` + `GeometryReader` + `SidebarWidthPreferenceKey` + `isDraggingDivider`. Inspired by Clearance's `OutlineSplitView` (at `/Users/lars/Documents/work/eigenes/clearance/clearance-main/apps/macos/Clearance/Views/OutlineSplitView.swift`) but adapted for a user-resizable sidebar instead of a fixed-width inspector.

- [ ] **Step 1: Create SidebarSplitView**

```swift
// minimark/Views/Window/SidebarSplitView.swift
import AppKit
import SwiftUI

struct SidebarSplitView<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebarWidth: CGFloat
    let sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    let onSidebarWidthChanged: (CGFloat) -> Void
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebarWidth = sidebarWidth
        self.sidebarPlacement = sidebarPlacement
        self.onSidebarWidthChanged = onSidebarWidthChanged
        self.sidebar = sidebar()
        self.detail = detail()
    }

    func makeNSViewController(context: Context) -> SidebarSplitViewController {
        SidebarSplitViewController(
            sidebar: AnyView(sidebar),
            detail: AnyView(detail),
            sidebarWidth: sidebarWidth,
            sidebarPlacement: sidebarPlacement,
            onSidebarWidthChanged: onSidebarWidthChanged
        )
    }

    func updateNSViewController(_ controller: SidebarSplitViewController, context: Context) {
        controller.update(
            sidebar: AnyView(sidebar),
            detail: AnyView(detail),
            sidebarWidth: sidebarWidth,
            sidebarPlacement: sidebarPlacement,
            onSidebarWidthChanged: onSidebarWidthChanged
        )
    }
}
```

- [ ] **Step 2: Create SidebarSplitViewController**

Append to the same file:

```swift
@MainActor
final class SidebarSplitViewController: NSSplitViewController {
    private static let sidebarMinWidth: CGFloat = ReaderSidebarWorkspaceMetrics.sidebarMinimumWidth
    private static let sidebarHoldingPriority: NSLayoutConstraint.Priority = .defaultHigh
    private static let dividerHitZone: CGFloat = 6

    private let sidebarHostingController: NSHostingController<AnyView>
    private let detailHostingController: NSHostingController<AnyView>
    private var sidebarItem: NSSplitViewItem
    private var detailItem: NSSplitViewItem

    private var currentSidebarWidth: CGFloat
    private var currentPlacement: ReaderMultiFileDisplayMode.SidebarPlacement
    private var onSidebarWidthChanged: (CGFloat) -> Void

    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var isDraggingDivider = false

    init(
        sidebar: AnyView,
        detail: AnyView,
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void
    ) {
        sidebarHostingController = NSHostingController(rootView: sidebar)
        detailHostingController = NSHostingController(rootView: detail)
        sidebarItem = NSSplitViewItem(viewController: sidebarHostingController)
        detailItem = NSSplitViewItem(viewController: detailHostingController)
        self.currentSidebarWidth = sidebarWidth
        self.currentPlacement = sidebarPlacement
        self.onSidebarWidthChanged = onSidebarWidthChanged

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarItem.minimumThickness = Self.sidebarMinWidth
        sidebarItem.holdingPriority = Self.sidebarHoldingPriority
        detailItem.minimumThickness = ReaderSidebarWorkspaceMetrics.detailMinimumWidth
        detailItem.holdingPriority = .defaultLow

        if sidebarPlacement == .left {
            addSplitViewItem(sidebarItem)
            addSplitViewItem(detailItem)
        } else {
            addSplitViewItem(detailItem)
            addSplitViewItem(sidebarItem)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applySidebarWidth(currentSidebarWidth)
        installMouseMonitors()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeMouseMonitors()
    }

    func update(
        sidebar: AnyView,
        detail: AnyView,
        sidebarWidth: CGFloat,
        sidebarPlacement: ReaderMultiFileDisplayMode.SidebarPlacement,
        onSidebarWidthChanged: @escaping (CGFloat) -> Void
    ) {
        sidebarHostingController.rootView = sidebar
        detailHostingController.rootView = detail
        self.onSidebarWidthChanged = onSidebarWidthChanged

        if sidebarPlacement != currentPlacement {
            currentPlacement = sidebarPlacement
            reorderItems(for: sidebarPlacement)
        }

        if !isDraggingDivider, abs(sidebarWidth - currentSidebarWidth) > 1 {
            currentSidebarWidth = sidebarWidth
            applySidebarWidth(sidebarWidth)
        }
    }

    // MARK: - Divider width management

    private func applySidebarWidth(_ width: CGFloat) {
        guard view.window != nil,
              splitView.arrangedSubviews.count > 1 else { return }

        let sidebarIndex = currentPlacement == .left ? 0 : 1
        let position: CGFloat
        if currentPlacement == .left {
            position = width
        } else {
            position = splitView.bounds.width - width - splitView.dividerThickness
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        splitView.setPosition(position, ofDividerAt: 0)
        CATransaction.commit()
    }

    private func reorderItems(for placement: ReaderMultiFileDisplayMode.SidebarPlacement) {
        removeSplitViewItem(sidebarItem)
        removeSplitViewItem(detailItem)

        if placement == .left {
            addSplitViewItem(sidebarItem)
            addSplitViewItem(detailItem)
        } else {
            addSplitViewItem(detailItem)
            addSplitViewItem(sidebarItem)
        }

        applySidebarWidth(currentSidebarWidth)
    }

    // MARK: - Mouse monitoring for divider drag

    private func installMouseMonitors() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDown(event)
            return event
        }
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }
    }

    private func removeMouseMonitors() {
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        mouseDownMonitor = nil
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor) }
        mouseUpMonitor = nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard splitView.subviews.count > 1,
              event.window === view.window else { return }

        let sidebarIndex = currentPlacement == .left ? 0 : 1
        let sidebarFrame = splitView.subviews[sidebarIndex].frame
        let location = splitView.convert(event.locationInWindow, from: nil)

        let dividerX = currentPlacement == .left ? sidebarFrame.maxX : sidebarFrame.minX
        if abs(location.x - dividerX) <= Self.dividerHitZone + splitView.dividerThickness {
            isDraggingDivider = true
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard isDraggingDivider else { return }
        isDraggingDivider = false

        let sidebarIndex = currentPlacement == .left ? 0 : 1
        guard splitView.subviews.count > 1 else { return }
        let finalWidth = splitView.subviews[sidebarIndex].frame.width
        if finalWidth > 0, abs(finalWidth - currentSidebarWidth) > 1 {
            currentSidebarWidth = finalWidth
            onSidebarWidthChanged(finalWidth)
        }
    }
}
```

Add the file to the Xcode project (same group as `SidebarDividerPositionSetter.swift` in `minimark/Views/Window/`).

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add minimark/Views/Window/SidebarSplitView.swift minimark.xcodeproj
git commit -m "feat: add SidebarSplitView wrapping NSSplitViewController for sidebar layout"
```

---

### Task 4: Extract SidebarScanProgressView

**Files:**
- Create: `minimark/Views/SidebarScanProgressView.swift`

Extract the scan progress footer from `ReaderSidebarWorkspaceView.sidebarWatchingFooter()` (lines 260-292) into a standalone view. This view will be rendered as an overlay so its updates don't invalidate the List.

- [ ] **Step 1: Create SidebarScanProgressView**

```swift
// minimark/Views/SidebarScanProgressView.swift
import SwiftUI

struct SidebarScanProgressView: View {
    @ObservedObject var controller: ReaderSidebarDocumentController

    var body: some View {
        if let session = controller.activeFolderWatchSession {
            VStack(spacing: 0) {
                Divider()
                footerContent(session: session)
            }
            .background(.bar)
        }
    }

    private func footerContent(session: ReaderFolderWatchSession) -> some View {
        HStack(spacing: 6) {
            if let progress = controller.contentScanProgress, !progress.isFinished {
                ProgressView(value: Double(progress.completed), total: max(Double(progress.total), 1))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 60)

                Text("Scanning \(progress.completed)/\(progress.total) files")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                if let fileCount = controller.scannedFileCount, fileCount > 0 {
                    Text("\(fileCount) \(fileCount == 1 ? "file" : "files")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Text(session.detailSummaryTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.3), value: controller.contentScanProgress?.isFinished)
    }
}
```

Add the file to the Xcode project (same group as other view files in `minimark/Views/`).

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add minimark/Views/SidebarScanProgressView.swift minimark.xcodeproj
git commit -m "feat: extract SidebarScanProgressView for isolated progress rendering"
```

---

### Task 5: Refactor ReaderSidebarDocumentRow to use SidebarRowState

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift` (lines 436-658, the private `ReaderSidebarDocumentRow` struct)

Replace `@ObservedObject var readerStore: ReaderStore` with `SidebarRowState` for body rendering. Keep `readerStore` as a plain `let` (non-observed) for the context menu's `openInApplications` access. Replace the per-row `TimelineView(.periodic(from: .now, by: 20))` with a `currentDate: Date` parameter from the parent.

- [ ] **Step 1: Update ReaderSidebarDocumentRow properties**

In `minimark/Views/ReaderSidebarWorkspaceView.swift`, replace the row struct's properties (lines 436-452):

Old:
```swift
private struct ReaderSidebarDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let documentID: UUID
    let documents: [ReaderSidebarDocumentController.Document]
    @ObservedObject var readerStore: ReaderStore
    let watchedDocumentIDs: Set<UUID>
    let selectedDocumentIDs: Set<UUID>
    let canClose: Bool
```

New:
```swift
private struct ReaderSidebarDocumentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let state: SidebarRowState
    let currentDate: Date
    let settings: ReaderSettings
    let documents: [ReaderSidebarDocumentController.Document]
    let readerStore: ReaderStore
    let watchedDocumentIDs: Set<UUID>
    let selectedDocumentIDs: Set<UUID>
    let canClose: Bool
```

Note: `documentID` is replaced by `state.id`. `readerStore` stays as a plain `let` (NOT `@ObservedObject`) for context menu access. `settings` is passed from the parent for indicator color computation.

- [ ] **Step 2: Update computed properties that read from readerStore**

Replace `indicatorState` (lines 522-527):
```swift
// Old:
private var indicatorState: ReaderDocumentIndicatorState {
    ReaderDocumentIndicatorState(
        hasUnacknowledgedExternalChange: readerStore.hasUnacknowledgedExternalChange,
        isCurrentFileMissing: readerStore.isCurrentFileMissing
    )
}

// New:
private var indicatorState: ReaderDocumentIndicatorState {
    state.indicatorState
}
```

Replace `changedIndicatorColor` (lines 518-520):
```swift
// Old:
private var changedIndicatorColor: Color {
    indicatorState.color(for: readerStore.currentSettings, colorScheme: colorScheme)
}

// New:
private var changedIndicatorColor: Color {
    indicatorState.color(for: settings, colorScheme: colorScheme)
}
```

Replace `isSelected` (lines 529-531):
```swift
// No change needed — still uses selectedDocumentIDs.contains(documentID)
// but update to use state.id:
private var isSelected: Bool {
    selectedDocumentIDs.contains(state.id)
}
```

Replace `title` (lines 636-642):
```swift
// Old:
private var title: String {
    if readerStore.fileDisplayName.isEmpty {
        return "Untitled"
    }
    return readerStore.fileDisplayName
}

// New:
private var title: String {
    state.title
}
```

Replace `lastChangedText` (lines 644-657):
```swift
// Old:
private func lastChangedText(relativeTo now: Date) -> String {
    if readerStore.isCurrentFileMissing {
        return "File deleted externally"
    }
    guard let fileLastModifiedAt = readerStore.fileLastModifiedAt else {
        return "No change timestamp"
    }
    return ReaderStatusFormatting.relativeText(
        for: fileLastModifiedAt,
        relativeTo: now
    )
}

// New:
private var lastChangedText: String {
    if state.isFileMissing {
        return "File deleted externally"
    }
    guard let fileLastModifiedAt = state.lastModified else {
        return "No change timestamp"
    }
    return ReaderStatusFormatting.relativeText(
        for: fileLastModifiedAt,
        relativeTo: currentDate
    )
}
```

Update `effectiveDocumentIDs` (lines 454-460) to use `state.id`:
```swift
private var effectiveDocumentIDs: Set<UUID> {
    if selectedDocumentIDs.contains(state.id), selectedDocumentIDs.count > 1 {
        return selectedDocumentIDs
    }
    return [state.id]
}
```

- [ ] **Step 3: Update the body to remove TimelineView**

Replace the body (lines 541-634). The key change is removing the `TimelineView` and using `lastChangedText` (now a computed property using `currentDate`):

```swift
var body: some View {
    HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(lastChangedText)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(lastChangedTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }

        Spacer(minLength: 8)

        if indicatorState.showsIndicator {
            Circle()
                .fill(changedIndicatorColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
        }

        if canClose {
            Button {
                onClose([state.id])
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isSelected ? 1 : 0)
            .allowsHitTesting(isHovered || isSelected)
            .accessibilityHidden(!(isHovered || isSelected))
            .help("Close")
        }
    }
    .padding(.vertical, 2)
    .accessibilityIdentifier("sidebar-document-\(title)")
    .onHover { hovering in
        isHovered = hovering
    }
    .contextMenu {
        if hasAnyOpenFile {
            Button(openInDefaultAppLabel) {
                onOpenInDefaultApp(effectiveDocumentIDs)
            }

            if !effectiveOpenInApplications.isEmpty {
                Menu(openInLabel) {
                    ForEach(effectiveOpenInApplications) { application in
                        Button(application.displayName) {
                            onOpenInApplication(application, effectiveDocumentIDs)
                        }
                    }
                }
            }

            Button(revealInFinderLabel) {
                onRevealInFinder(effectiveDocumentIDs)
            }
        }

        if watchingDocumentCount > 0 {
            Divider()

            Button(stopWatchingLabel) {
                onStopWatchingFolders(effectiveDocumentIDs)
            }
        }

        if canClose {
            Divider()

            Button(closeLabel) {
                onClose(effectiveDocumentIDs)
            }

            if effectiveDocumentIDs.count < documents.count {
                Button(closeOtherLabel) {
                    onCloseOthers(effectiveDocumentIDs)
                }
            }

            Button("Close All Files") {
                onCloseAll()
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD FAILED — the `documentRow(for:allDocuments:)` call site (line 298) still passes old parameters. This is expected; Task 6 will fix the call site.

Note: If you want to verify in isolation, temporarily update the `documentRow` method (step 5 below) before building.

- [ ] **Step 5: Update the documentRow method call site**

Update `documentRow(for:allDocuments:)` (lines 294-317) to pass the new parameters:

```swift
private func documentRow(
    for document: ReaderSidebarDocumentController.Document,
    allDocuments: [ReaderSidebarDocumentController.Document],
    currentDate: Date
) -> some View {
    let rowState = controller.rowStates.first(where: { $0.id == document.id })
        ?? SidebarRowState(
            id: document.id,
            title: document.readerStore.fileDisplayName.isEmpty ? "Untitled" : document.readerStore.fileDisplayName,
            lastModified: document.readerStore.fileLastModifiedAt,
            isFileMissing: document.readerStore.isCurrentFileMissing,
            indicatorState: ReaderDocumentIndicatorState(
                hasUnacknowledgedExternalChange: document.readerStore.hasUnacknowledgedExternalChange,
                isCurrentFileMissing: document.readerStore.isCurrentFileMissing
            )
        )

    return ReaderSidebarDocumentRow(
        state: rowState,
        currentDate: currentDate,
        settings: settingsStore.currentSettings,
        documents: allDocuments,
        readerStore: document.readerStore,
        watchedDocumentIDs: watchedDocumentIDs,
        selectedDocumentIDs: selectedDocumentIDs,
        canClose: true,
        onOpenInDefaultApp: onOpenInDefaultApp,
        onOpenInApplication: { application, documentIDs in
            onOpenInApplication(application, documentIDs)
        },
        onRevealInFinder: onRevealInFinder,
        onStopWatchingFolders: onStopWatchingFolders,
        onClose: onCloseDocuments,
        onCloseOthers: onCloseOtherDocuments,
        onCloseAll: {
            onCloseAllDocuments()
        }
    )
}
```

Update the call sites in `sidebarColumn` (lines 178 and 185) to pass `currentDate` — this will be wired in Task 6 when the TimelineView wrapper is added. For now, use `Date()` as a placeholder so it compiles:

```swift
// line 178:
documentRow(for: document, allDocuments: sortedDocuments, currentDate: Date())
// line 185:
documentRow(for: document, allDocuments: sortedDocuments, currentDate: Date())
```

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "refactor: replace per-row ReaderStore observation with SidebarRowState value type"
```

---

### Task 6: Refactor ReaderSidebarWorkspaceView — wire SidebarSplitView, TimelineView, and overlay

**Files:**
- Modify: `minimark/Views/ReaderSidebarWorkspaceView.swift`

This task replaces HSplitView with SidebarSplitView, wraps the List in a 5s TimelineView, renders scan progress as an overlay, and removes all dead code (SidebarWidthPreferenceKey, isDraggingDivider, GeometryReader, SidebarDividerPositionSetter references).

- [ ] **Step 1: Remove dead code from the top of the file**

Delete `SidebarWidthPreferenceKey` (lines 10-16):
```swift
// DELETE these lines:
private struct SidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
```

Remove `isDraggingDivider` state (line 37):
```swift
// DELETE this line:
@State private var isDraggingDivider = false
```

- [ ] **Step 2: Replace HSplitView with SidebarSplitView in body**

Replace the body (lines 39-78):

```swift
var body: some View {
    Group {
        if controller.documents.count > 1 {
            SidebarSplitView(
                sidebarWidth: sidebarWidth,
                sidebarPlacement: sidebarPlacement,
                onSidebarWidthChanged: { newWidth in
                    sidebarWidth = newWidth
                }
            ) {
                sidebarColumn
            } detail: {
                detailColumn
            }
        } else {
            detail(controller.selectedReaderStore)
        }
    }
    .onAppear {
        selectedDocumentIDs = [controller.selectedDocumentID]
    }
    .onChange(of: controller.selectedDocumentID) { _, selectedDocumentID in
        if !selectedDocumentIDs.contains(selectedDocumentID) || selectedDocumentIDs.isEmpty {
            selectedDocumentIDs = [selectedDocumentID]
        }
    }
    .onChange(of: controller.documents.map(\.id)) { _, documentIDs in
        let validIDs = Set(documentIDs)
        let filteredSelection = selectedDocumentIDs.intersection(validIDs)
        if filteredSelection.isEmpty, let firstDocumentID = displayedDocuments.first?.id {
            selectedDocumentIDs = [firstDocumentID]
            scheduleControllerSelection(firstDocumentID)
        } else if filteredSelection != selectedDocumentIDs {
            selectedDocumentIDs = filteredSelection
        }
    }
    .onChange(of: activeDirectoryPaths) { _, paths in
        let activeGroupIDs = Set(paths)
        collapsedGroupIDs.formIntersection(activeGroupIDs)
        pinnedGroupIDs.formIntersection(activeGroupIDs)
    }
}
```

- [ ] **Step 3: Rewrite sidebarColumn with TimelineView and overlay**

Replace the entire `sidebarColumn` computed property (lines 160-244) with:

```swift
private var sidebarColumn: some View {
    let sortedDocuments = displayedDocuments
    let grouping = sidebarGrouping(for: sortedDocuments)

    return ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
            sidebarToolbar

            Divider()

            TimelineView(.periodic(from: .now, by: 5)) { context in
                List(
                    selection: Binding(
                        get: { selectedDocumentIDs },
                        set: { updateSelection($0) }
                    )
                ) {
                    switch grouping {
                    case .flat(let documents):
                        ForEach(documents) { document in
                            documentRow(for: document, allDocuments: sortedDocuments, currentDate: context.date)
                                .tag(document.id)
                        }
                    case .grouped(let groups):
                        ForEach(groups) { group in
                            DisclosureGroup(isExpanded: isGroupExpanded(group.id)) {
                                ForEach(group.documents) { document in
                                    documentRow(for: document, allDocuments: sortedDocuments, currentDate: context.date)
                                        .tag(document.id)
                                }
                            } label: {
                                ReaderSidebarGroupHeader(
                                    displayName: group.displayName,
                                    documentCount: group.documents.count,
                                    isPinned: group.isPinned,
                                    indicatorState: group.indicatorState,
                                    settings: settingsStore.currentSettings,
                                    onTogglePin: {
                                        toggleGroupPin(group.id)
                                    },
                                    onCloseGroup: {
                                        onCloseDocuments(Set(group.documents.map(\.id)))
                                    }
                                )
                            }
                            .disclosureGroupStyle(SidebarGroupDisclosureStyle())
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxHeight: .infinity)

        SidebarScanProgressView(controller: controller)
    }
    .accessibilityIdentifier("sidebar-column")
}
```

Note: The `.frame()` modifier with `minWidth`/`idealWidth`/`maxWidth` is removed entirely — the NSSplitViewController manages sidebar width now. The GeometryReader background, SidebarDividerPositionSetter background, and onPreferenceChange handler are all removed.

- [ ] **Step 4: Remove detailColumn frame constraints**

Replace `detailColumn` (lines 319-326):

```swift
// Old:
private var detailColumn: some View {
    detail(controller.selectedReaderStore)
        .frame(
            minWidth: ReaderSidebarWorkspaceMetrics.detailMinimumWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
        )
}

// New:
private var detailColumn: some View {
    detail(controller.selectedReaderStore)
}
```

The NSSplitViewController's `detailItem.minimumThickness` handles the minimum width now.

- [ ] **Step 5: Remove sidebarWatchingFooter method**

Delete the entire `sidebarWatchingFooter(session:)` method (lines 260-292) — its content now lives in `SidebarScanProgressView`.

- [ ] **Step 6: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Run all tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -10`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "refactor: replace HSplitView with SidebarSplitView, add 5s TimelineView, overlay scan progress"
```

---

### Task 7: Update ReaderWindowRootView

**Files:**
- Modify: `minimark/Views/ReaderWindowRootView.swift`

The `sidebarWidth` binding is no longer passed to `ReaderSidebarWorkspaceView` — width is now managed by `SidebarSplitView` internally and reported via callback. Update the root view accordingly.

- [ ] **Step 1: Remove sidebarWidth binding from ReaderSidebarWorkspaceView init**

In the `rootContent` view builder (lines 419-458), remove the `sidebarWidth: $sidebarWidth` line:

```swift
// Remove this line from the ReaderSidebarWorkspaceView init:
sidebarWidth: $sidebarWidth,
```

- [ ] **Step 2: Update ReaderSidebarWorkspaceView to accept sidebarWidth as a let + callback**

This requires updating `ReaderSidebarWorkspaceView` to change `@Binding var sidebarWidth: CGFloat` to `let sidebarWidth: CGFloat` and add an `onSidebarWidthChanged` closure. In `minimark/Views/ReaderSidebarWorkspaceView.swift`:

Replace:
```swift
@Binding var sidebarWidth: CGFloat
```

With:
```swift
let sidebarWidth: CGFloat
let onSidebarWidthChanged: (CGFloat) -> Void
```

Update the `SidebarSplitView` usage in the body to use the callback:
```swift
SidebarSplitView(
    sidebarWidth: sidebarWidth,
    sidebarPlacement: sidebarPlacement,
    onSidebarWidthChanged: onSidebarWidthChanged
) {
```

Then in `ReaderWindowRootView.rootContent`, pass both:
```swift
ReaderSidebarWorkspaceView(
    controller: sidebarDocumentController,
    settingsStore: settingsStore,
    sidebarPlacement: sidebarPlacement,
    collapsedGroupIDs: $sidebarCollapsedGroupIDs,
    pinnedGroupIDs: $sidebarPinnedGroupIDs,
    fileSortMode: fileSortModeBinding,
    groupSortMode: groupSortModeBinding,
    sidebarWidth: sidebarWidth,
    onSidebarWidthChanged: { newWidth in
        sidebarWidth = newWidth
        if activeFavoriteWorkspaceState != nil,
           sidebarDocumentController.documents.count > 1 {
            activeFavoriteWorkspaceState?.sidebarWidth = newWidth
        }
    },
    detail: { store in
        contentView(for: store)
    },
    // ... remaining closures unchanged
```

- [ ] **Step 3: Remove old sidebarWidth onChange handler**

Delete the `onChange(of: sidebarWidth)` handler (lines 274-279) from `ReaderWindowRootView` — the persistence logic is now inside the `onSidebarWidthChanged` callback above:

```swift
// DELETE:
.onChange(of: sidebarWidth) { _, newWidth in
    if activeFavoriteWorkspaceState != nil,
       sidebarDocumentController.documents.count > 1 {
        activeFavoriteWorkspaceState?.sidebarWidth = newWidth
    }
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add minimark/Views/ReaderWindowRootView.swift minimark/Views/ReaderSidebarWorkspaceView.swift
git commit -m "refactor: replace sidebarWidth binding with callback-based width reporting"
```

---

### Task 8: Delete SidebarDividerPositionSetter and clean up

**Files:**
- Delete: `minimark/Views/Window/SidebarDividerPositionSetter.swift`

- [ ] **Step 1: Verify no remaining references**

Search for any remaining references to the deleted components:

```bash
grep -r "SidebarDividerPositionSetter\|SidebarWidthPreferenceKey\|isDraggingDivider" minimark/ --include="*.swift"
```

Expected: No results (all references were removed in Tasks 5-7).

- [ ] **Step 2: Delete the file**

```bash
git rm minimark/Views/Window/SidebarDividerPositionSetter.swift
```

Remove the file reference from the Xcode project as well.

- [ ] **Step 3: Build to verify nothing is broken**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run full test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -10`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: delete SidebarDividerPositionSetter, replaced by SidebarSplitView"
```

---

### Task 9: Final verification

- [ ] **Step 1: Full clean build**

```bash
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug clean && \
xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Full test suite**

```bash
xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -10
```

Expected: All tests PASS

- [ ] **Step 3: Manual smoke test checklist**

Build and run the app. Verify:
- Open a folder with 30+ markdown files
- Drag the sidebar divider — should be smooth, no stuttering
- Resize the window — sidebar width should stay fixed (original #71 behavior preserved)
- Toggle sidebar placement (left/right) — should work correctly
- Verify relative timestamps update every ~5 seconds for recent files
- Verify scan progress bar shows during initial folder scan without freezing the sidebar
- Close files, open files, switch between documents — all should work as before
