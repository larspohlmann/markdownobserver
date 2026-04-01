# Loading Spinner Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a loading spinner overlay when switching tabs or opening files, decoupling the tab switch from content loading so the UI stays responsive.

**Architecture:** Add a `.loading` case to `ReaderDocumentLoadState`. Callers that trigger file loading (`selectDocument`, `openDocumentInSelectedSlot`, etc.) set `.loading` immediately, then dispatch the actual I/O in a `Task` after a `yield()` so SwiftUI gets a render pass to show the overlay. The existing `DocumentLoadingOverlay` is parameterized for context-specific messaging.

**Tech Stack:** SwiftUI, Combine, Swift Testing

---

### Task 1: Add `.loading` case to `ReaderDocumentLoadState`

**Files:**
- Modify: `minimark/Stores/Types/ReaderStoreTypes.swift:31-35`
- Modify: `minimark/Stores/ReaderStore.swift:201-203,289-306`
- Test: `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`

- [ ] **Step 1: Write the failing test — `transitionToLoading` sets loading state**

Add to `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`, before the closing `}` of the struct:

```swift
    @Test @MainActor func transitionToLoadingSetsLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        #expect(store.documentLoadState == .deferred)

        store.transitionToLoading()

        #expect(store.documentLoadState == .loading)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/transitionToLoadingSetsLoadingState 2>&1 | tail -20`

Expected: FAIL — `transitionToLoading()` does not exist, `.loading` does not exist.

- [ ] **Step 3: Add `.loading` case and `transitionToLoading()` method**

In `minimark/Stores/Types/ReaderStoreTypes.swift`, change the enum to:

```swift
enum ReaderDocumentLoadState: Equatable, Sendable {
    case ready
    case loading
    case deferred
    case settlingAutoOpen
}
```

In `minimark/Stores/ReaderStore.swift`, add a new method after `clearDeferredLoadState()` (after line 306):

```swift
    func transitionToLoading() {
        guard documentLoadState == .deferred || documentLoadState == .ready else { return }
        documentLoadState = .loading
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/transitionToLoadingSetsLoadingState 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add minimark/Stores/Types/ReaderStoreTypes.swift minimark/Stores/ReaderStore.swift minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift
git commit -m "feat(#59): add .loading case to ReaderDocumentLoadState with transitionToLoading()"
```

---

### Task 2: Update `materializeDeferredDocument` to accept `.loading` state

**Files:**
- Modify: `minimark/Stores/Coordination/ReaderStore+DocumentOpenFlow.swift:99-120`
- Test: `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`

- [ ] **Step 1: Write the failing test — materialize works when state is `.loading`**

Add to `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`:

```swift
    @Test @MainActor func materializeDeferredDocumentWorksFromLoadingState() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.documents[0].readerStore
        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        store.deferFile(at: harness.primaryFileURL, folderWatchSession: session)
        store.transitionToLoading()
        #expect(store.documentLoadState == .loading)

        store.materializeDeferredDocument()

        #expect(store.documentLoadState == .ready || store.documentLoadState == .settlingAutoOpen)
        #expect(!store.sourceMarkdown.isEmpty)
        #expect(!store.renderedHTMLDocument.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/materializeDeferredDocumentWorksFromLoadingState 2>&1 | tail -20`

Expected: FAIL — `materializeDeferredDocument()` early-returns because `isDeferredDocument` is false when state is `.loading`.

- [ ] **Step 3: Update `materializeDeferredDocument` guard and state transition**

In `minimark/Stores/Coordination/ReaderStore+DocumentOpenFlow.swift`, replace `materializeDeferredDocument` (lines 99-120) with:

```swift
    func materializeDeferredDocument(
        origin: ReaderOpenOrigin? = nil,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        guard documentLoadState == .deferred || documentLoadState == .loading,
              let url = fileURL else {
            return
        }

        if documentLoadState == .deferred {
            documentLoadState = .loading
        }

        openFile(
            at: url,
            origin: origin ?? currentOpenOrigin,
            folderWatchSession: folderWatchSession ?? activeFolderWatchSession,
            initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
        )

        // Safety: if openFile failed internally, clear the loading state
        if documentLoadState == .loading {
            documentLoadState = .ready
        }

        if initialDiffBaselineMarkdown != nil {
            noteObservedExternalChange()
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/materializeDeferredDocumentWorksFromLoadingState 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Run all deferred loading tests to check nothing broke**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests 2>&1 | tail -30`

Expected: All 14 tests PASS (12 existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add minimark/Stores/Coordination/ReaderStore+DocumentOpenFlow.swift minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift
git commit -m "feat(#59): update materializeDeferredDocument to accept .loading state"
```

---

### Task 3: Make `selectDocument` dispatch deferred materialization asynchronously

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift:78-95`
- Test: `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`

- [ ] **Step 1: Write the failing test — selecting deferred doc sets `.loading` immediately**

Add to `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`:

```swift
    @Test @MainActor func selectingDeferredDocumentSetsLoadingStateImmediately() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        let deferredDocument = harness.controller.documents.first {
            $0.id != harness.controller.selectedDocumentID
        }!
        #expect(deferredDocument.readerStore.documentLoadState == .deferred)

        harness.controller.selectDocument(deferredDocument.id)

        // Immediately after selectDocument: state should be .loading, not yet fully loaded
        #expect(deferredDocument.readerStore.documentLoadState == .loading)
        #expect(deferredDocument.readerStore.sourceMarkdown.isEmpty)

        // After yielding: the Task completes and the document is fully loaded
        await Task.yield()
        #expect(deferredDocument.readerStore.documentLoadState == .ready || deferredDocument.readerStore.documentLoadState == .settlingAutoOpen)
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/selectingDeferredDocumentSetsLoadingStateImmediately 2>&1 | tail -20`

Expected: FAIL — `selectDocument` currently calls `materializeDeferredDocument()` synchronously, so the state jumps straight past `.loading` to `.ready`.

- [ ] **Step 3: Make `selectDocument` async for deferred documents**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, replace `selectDocument` (lines 78-95) with:

```swift
    func selectDocument(_ documentID: UUID?) {
        guard let documentID,
              documents.contains(where: { $0.id == documentID }) else {
            return
        }

        if selectedDocumentID == documentID {
            return
        }

        selectedDocumentID = documentID
        let store = selectedReaderStore

        if store.isDeferredDocument {
            store.transitionToLoading()
            bindSelectedStore()
            Task { @MainActor in
                await Task.yield()
                store.materializeDeferredDocument()
            }
        } else {
            bindSelectedStore()
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/selectingDeferredDocumentSetsLoadingStateImmediately 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Update the existing `selectingDeferredDocumentMaterializesIt` test for async**

The existing test (lines 117-147) expects synchronous materialization. Update it to await the Task:

```swift
    @Test @MainActor func selectingDeferredDocumentMaterializesIt() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        // Find the non-selected deferred document
        let deferredDocument = harness.controller.documents.first {
            $0.id != harness.controller.selectedDocumentID
        }!
        #expect(deferredDocument.readerStore.isDeferredDocument)

        // Select it
        harness.controller.selectDocument(deferredDocument.id)

        // Wait for async materialization
        await Task.yield()

        // Now it should be fully loaded
        #expect(!deferredDocument.readerStore.isDeferredDocument)
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }
```

- [ ] **Step 6: Run all deferred loading tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 7: Run the full sidebar test suites to check for regressions**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests 2>&1 | tail -30`

Expected: All tests PASS. Some tests that call `selectDocument` on deferred docs may now need `await Task.yield()` — fix any that fail.

- [ ] **Step 8: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift
git commit -m "feat(#59): make selectDocument dispatch deferred materialization asynchronously"
```

---

### Task 4: Make `openDocumentInSelectedSlot` use loading state

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift:97-122`
- Test: `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`

- [ ] **Step 1: Write the failing test — openDocumentInSelectedSlot sets `.loading` immediately**

Add to `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`:

```swift
    @Test @MainActor func openDocumentInSelectedSlotSetsLoadingState() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let store = harness.controller.selectedReaderStore

        harness.controller.openDocumentInSelectedSlot(
            at: harness.primaryFileURL,
            origin: .manual
        )

        // Immediately: state should be .loading
        #expect(store.documentLoadState == .loading)

        // After yield: fully loaded
        await Task.yield()
        #expect(store.documentLoadState == .ready || store.documentLoadState == .settlingAutoOpen)
        #expect(!store.sourceMarkdown.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/openDocumentInSelectedSlotSetsLoadingState 2>&1 | tail -20`

Expected: FAIL — `openDocumentInSelectedSlot` currently calls `openFile` synchronously, so state jumps straight to `.ready`.

- [ ] **Step 3: Make `openDocumentInSelectedSlot` async**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, replace `openDocumentInSelectedSlot` (lines 97-122) with:

```swift
    func openDocumentInSelectedSlot(
        at fileURL: URL,
        origin: ReaderOpenOrigin,
        folderWatchSession: ReaderFolderWatchSession? = nil,
        initialDiffBaselineMarkdown: String? = nil
    ) {
        let normalizedFileURL = ReaderFileRouting.normalizedFileURL(fileURL)
        if let existingDocument = document(for: normalizedFileURL) {
            selectDocument(existingDocument.id)
            return
        }

        let document = selectedDocument ?? documents[0]
        let effectiveFolderWatchSession = resolvedFolderWatchSession(
            for: normalizedFileURL,
            requestedSession: folderWatchSession
        )
        document.readerStore.transitionToLoading()
        selectedDocumentID = document.id
        bindSelectedStore()

        Task { @MainActor in
            await Task.yield()
            document.readerStore.openFile(
                at: normalizedFileURL,
                origin: origin,
                folderWatchSession: effectiveFolderWatchSession,
                initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
            )
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests/openDocumentInSelectedSlotSetsLoadingState 2>&1 | tail -20`

Expected: PASS

- [ ] **Step 5: Update existing `openDocumentInSelectedSlotOnDeferredDocumentReplacesCleanly` test**

The existing test (lines 176-201) expects synchronous loading. Update it to `async` and add `await Task.yield()`:

```swift
    @Test @MainActor func openDocumentInSelectedSlotOnDeferredDocumentReplacesCleanly() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("gamma.md")
        try "# Gamma".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        harness.controller.openDocumentInSelectedSlot(at: thirdFileURL, origin: .manual)
        await Task.yield()

        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "gamma.md")
        #expect(!harness.controller.selectedReaderStore.isDeferredDocument)
        #expect(!harness.controller.selectedReaderStore.sourceMarkdown.isEmpty)
    }
```

- [ ] **Step 6: Run all deferred loading tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift
git commit -m "feat(#59): make openDocumentInSelectedSlot use loading state with async dispatch"
```

---

### Task 5: Make `openDocumentsBurst` and `openAdditionalDocument` deferred paths async

**Files:**
- Modify: `minimark/Stores/ReaderSidebarDocumentController.swift:124-222`
- Test: `minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift`

- [ ] **Step 1: Update `openDocumentsBurst` final materialization to be async**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, replace the tail of `openDocumentsBurst` (lines 219-222):

```swift
        if selectedReaderStore.isDeferredDocument {
            selectedReaderStore.materializeDeferredDocument()
        }
```

with:

```swift
        if selectedReaderStore.isDeferredDocument {
            let store = selectedReaderStore
            store.transitionToLoading()
            Task { @MainActor in
                await Task.yield()
                store.materializeDeferredDocument()
            }
        }
```

- [ ] **Step 2: Update `openAdditionalDocument` deferred materialization to be async**

In `minimark/Stores/ReaderSidebarDocumentController.swift`, in `openAdditionalDocument`, replace the block (lines 132-144):

```swift
        if let existingDocument = document(for: normalizedFileURL) {
            if existingDocument.readerStore.isDeferredDocument {
                existingDocument.readerStore.materializeDeferredDocument(
                    origin: origin,
                    folderWatchSession: resolvedFolderWatchSession(
                        for: normalizedFileURL,
                        requestedSession: folderWatchSession
                    ),
                    initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                )
            }
            selectDocument(existingDocument.id)
            return
        }
```

with:

```swift
        if let existingDocument = document(for: normalizedFileURL) {
            if existingDocument.readerStore.isDeferredDocument {
                let store = existingDocument.readerStore
                store.transitionToLoading()
                let effectiveSession = resolvedFolderWatchSession(
                    for: normalizedFileURL,
                    requestedSession: folderWatchSession
                )
                selectDocument(existingDocument.id)
                Task { @MainActor in
                    await Task.yield()
                    store.materializeDeferredDocument(
                        origin: origin,
                        folderWatchSession: effectiveSession,
                        initialDiffBaselineMarkdown: initialDiffBaselineMarkdown
                    )
                }
            } else {
                selectDocument(existingDocument.id)
            }
            return
        }
```

- [ ] **Step 3: Update affected existing tests to await async materialization**

Update `liveChangeEventFullyLoadsDeferredDocument` (lines 233-268) to be `async` and add `await Task.yield()` before asserting full load:

```swift
    @Test @MainActor func liveChangeEventFullyLoadsDeferredDocument() async throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let session = ReaderFolderWatchSession(
            folderURL: harness.temporaryDirectoryURL,
            options: .default,
            startedAt: .now
        )

        harness.controller.openDocumentsBurst(
            at: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            folderWatchSession: session,
            preferEmptySelection: true
        )
        await Task.yield()

        // Find the deferred (non-selected) document
        let deferredDocument = harness.controller.documents.first {
            $0.readerStore.isDeferredDocument
        }!
        #expect(deferredDocument.readerStore.sourceMarkdown.isEmpty)

        // Simulate a live folder-watch change event for the deferred file
        harness.controller.openAdditionalDocument(
            at: deferredDocument.readerStore.fileURL!,
            origin: .folderWatchAutoOpen,
            folderWatchSession: session,
            initialDiffBaselineMarkdown: "# Old content"
        )
        await Task.yield()

        // The deferred document should now be fully loaded
        #expect(!deferredDocument.readerStore.isDeferredDocument)
        #expect(!deferredDocument.readerStore.sourceMarkdown.isEmpty)
        #expect(!deferredDocument.readerStore.renderedHTMLDocument.isEmpty)
    }
```

Update `liveChangeEventShowsIndicatorForDeferredDocument` (lines 270-301) similarly — make it `async`, add `await Task.yield()` after `openAdditionalDocument`.

Update `liveAddEventDoesNotShowIndicatorForDeferredDocument` (lines 303-334) similarly — make it `async`, add `await Task.yield()` after `openAdditionalDocument`.

- [ ] **Step 4: Run all deferred loading tests**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDeferredLoadingTests 2>&1 | tail -30`

Expected: All tests PASS.

- [ ] **Step 5: Run full sidebar and folder watch test suites**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests/ReaderSidebarDocumentControllerTests -only-testing:minimarkTests/FolderWatchCoordinationTests 2>&1 | tail -30`

Expected: All tests PASS. Fix any tests that assumed synchronous materialization by adding `await Task.yield()`.

- [ ] **Step 6: Commit**

```bash
git add minimark/Stores/ReaderSidebarDocumentController.swift minimarkTests/Sidebar/ReaderSidebarDeferredLoadingTests.swift
git commit -m "feat(#59): make openDocumentsBurst and openAdditionalDocument deferred paths async"
```

---

### Task 6: Parameterize `DocumentLoadingOverlay` and broaden overlay condition

**Files:**
- Modify: `minimark/Views/Content/ContentDocumentSurfaceViews.swift:1-27`
- Modify: `minimark/ContentView.swift:495-503,530-532,862-886`

- [ ] **Step 1: Parameterize `DocumentLoadingOverlay`**

In `minimark/Views/Content/ContentDocumentSurfaceViews.swift`, replace `DocumentLoadingOverlay` (lines 1-27) with:

```swift
import SwiftUI

struct DocumentLoadingOverlay: View {
    let theme: ReaderTheme
    let headline: String
    let subtitle: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(hex: theme.backgroundHex) ?? .clear)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color(hex: theme.foregroundHex) ?? .primary)

                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Color(hex: theme.foregroundHex) ?? .primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: theme.secondaryForegroundHex) ?? .secondary)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Broaden overlay condition and add message properties in `ContentView`**

In `minimark/ContentView.swift`, replace `shouldShowDocumentLoadingOverlay` (line 530-532) with:

```swift
    private var shouldShowDocumentLoadingOverlay: Bool {
        readerStore.documentLoadState == .loading || readerStore.documentLoadState == .settlingAutoOpen
    }

    private var loadingOverlayHeadline: String {
        switch readerStore.documentLoadState {
        case .settlingAutoOpen:
            return "Waiting for file contents\u{2026}"
        default:
            return "Loading document\u{2026}"
        }
    }

    private var loadingOverlaySubtitle: String? {
        switch readerStore.documentLoadState {
        case .settlingAutoOpen:
            return "The new watched document will appear as soon as writing finishes."
        default:
            return nil
        }
    }
```

- [ ] **Step 3: Update `DocumentSurfaceLayoutView` to pass headline/subtitle**

In `minimark/ContentView.swift`, update `DocumentSurfaceLayoutView` struct (around line 862) to accept and forward the new parameters:

```swift
private struct DocumentSurfaceLayoutView<PreviewSurface: View, SourceSurface: View>: View {
    let documentViewMode: ReaderDocumentViewMode
    let showsLoadingOverlay: Bool
    let loadingOverlayHeadline: String
    let loadingOverlaySubtitle: String?
    let currentReaderTheme: ReaderTheme
    let previewSurface: PreviewSurface
    let sourceSurface: SourceSurface

    var body: some View {
        if showsLoadingOverlay {
            DocumentLoadingOverlay(
                theme: currentReaderTheme,
                headline: loadingOverlayHeadline,
                subtitle: loadingOverlaySubtitle
            )
        } else {
            switch documentViewMode {
            case .preview:
                previewSurface
            case .split:
                HSplitView {
                    previewSurface
                    sourceSurface
                }
            case .source:
                sourceSurface
            }
        }
    }
}
```

- [ ] **Step 4: Update the `documentSurfaceLayout` call site**

In `minimark/ContentView.swift`, update `documentSurfaceLayout` (around line 495) to pass the new parameters:

```swift
    private var documentSurfaceLayout: some View {
        DocumentSurfaceLayoutView(
            documentViewMode: readerStore.documentViewMode,
            showsLoadingOverlay: shouldShowDocumentLoadingOverlay,
            loadingOverlayHeadline: loadingOverlayHeadline,
            loadingOverlaySubtitle: loadingOverlaySubtitle,
            currentReaderTheme: currentReaderTheme,
            previewSurface: documentSurfacePane(for: .preview),
            sourceSurface: documentSurfacePane(for: .source)
        )
    }
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild -project minimark.xcodeproj -scheme minimark -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -20`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add minimark/Views/Content/ContentDocumentSurfaceViews.swift minimark/ContentView.swift
git commit -m "feat(#59): parameterize DocumentLoadingOverlay and broaden overlay to .loading state"
```

---

### Task 7: Full build and test verification

**Files:** None (verification only)

- [ ] **Step 1: Run full unit test suite**

Run: `xcodebuild test -project minimark.xcodeproj -scheme minimark -destination 'platform=macOS' -only-testing:minimarkTests 2>&1 | tail -40`

Expected: All tests PASS. If any fail, diagnose and fix before proceeding.

- [ ] **Step 2: Fix any test failures**

If tests fail because they assumed synchronous `selectDocument`/`openDocumentInSelectedSlot`/`openDocumentsBurst` behavior, update them by:
1. Making the test function `async`
2. Adding `await Task.yield()` after the call that now dispatches a Task

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix(#59): update remaining tests for async loading state transitions"
```

- [ ] **Step 4: Remove `clearDeferredLoadState()` if no longer needed**

Check if `clearDeferredLoadState()` is still called anywhere. If `materializeDeferredDocument` no longer calls it (replaced by inline logic in Task 2), remove it from `ReaderStore.swift` (lines 303-306).

Run: `grep -r "clearDeferredLoadState" minimark/ minimarkTests/`

If no references remain, delete the method and commit:

```bash
git add minimark/Stores/ReaderStore.swift
git commit -m "refactor(#59): remove unused clearDeferredLoadState()"
```
