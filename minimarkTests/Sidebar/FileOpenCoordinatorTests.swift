import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct FileOpenCoordinatorTests {

    // MARK: - Plan building: reuseEmptySlotForFirst

    @Test @MainActor func planForThreeFilesOnEmptyWindowReusesFirstSlot() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL, thirdFileURL],
            origin: .manual,
            slotStrategy: .reuseEmptySlotForFirst
        ))

        #expect(plan.assignments.count == 3)
        #expect(plan.assignments[0].target == .reuseExisting(documentID: harness.controller.selectedDocumentID))
        #expect(plan.assignments[1].target == .createNew)
        #expect(plan.assignments[2].target == .createNew)
    }

    @Test @MainActor func planForFilesOnNonEmptyWindowAlwaysCreatesNew() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.secondaryFileURL],
            origin: .manual,
            slotStrategy: .reuseEmptySlotForFirst
        ))

        #expect(plan.assignments.count == 1)
        #expect(plan.assignments[0].target == .createNew)
    }

    // MARK: - Plan building: deduplication

    @Test @MainActor func planDeduplicatesDuplicateURLs() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL, harness.primaryFileURL],
            origin: .manual
        ))

        #expect(plan.assignments.count == 2)
    }

    @Test @MainActor func planFocusesAlreadyOpenURLAndAppendsNew() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        let existingDocID = harness.controller.documents.first(where: {
            $0.readerStore.fileURL?.lastPathComponent == "alpha.md"
        })!.id

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))

        #expect(plan.assignments.count == 2)
        #expect(plan.assignments[0].target == .reuseExisting(documentID: existingDocID))
        #expect(plan.assignments[0].fileURL.lastPathComponent == "alpha.md")
        #expect(plan.assignments[1].target == .createNew)
        #expect(plan.assignments[1].fileURL.lastPathComponent == "zeta.md")
    }

    // MARK: - Plan building: alwaysAppend

    @Test @MainActor func planWithAlwaysAppendNeverReusesEmptySlot() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))

        #expect(plan.assignments.count == 1)
        #expect(plan.assignments[0].target == .createNew)
    }

    // MARK: - Plan building: replaceSelectedSlot

    @Test @MainActor func planWithReplaceSelectedSlotTargetsSelectedDocument() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let selectedID = harness.controller.selectedDocumentID

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        #expect(plan.assignments.count == 1)
        #expect(plan.assignments[0].target == .reuseExisting(documentID: selectedID))
    }

    // MARK: - Plan building: materialization strategies

    @Test @MainActor func planWithLoadAllSetsLoadFully() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            materializationStrategy: .loadAll
        ))

        #expect(plan.assignments[0].loadMode == .loadFully)
    }

    @Test @MainActor func planWithDeferThenMaterializeSetsDeferOnly() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            materializationStrategy: .deferThenMaterializeNewest(count: 12)
        ))

        #expect(plan.assignments[0].loadMode == .deferOnly)
        #expect(plan.materializationStrategy == .deferThenMaterializeNewest(count: 12))
    }

    // MARK: - Plan building: diff baseline passthrough

    @Test @MainActor func planPassesThroughDiffBaseline() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let normalizedURL = ReaderFileRouting.normalizedFileURL(harness.primaryFileURL)

        let plan = coordinator.buildPlan(for: FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            initialDiffBaselineMarkdownByURL: [normalizedURL: "# Old"]
        ))

        #expect(plan.assignments[0].initialDiffBaselineMarkdown == "# Old")
    }

    // MARK: - End-to-end: regression test for #85

    @Test @MainActor func openThreeFilesOnEmptyWindowOpensAllThree() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        let thirdFileURL = harness.temporaryDirectoryURL.appendingPathComponent("beta.md")
        try "# Beta".write(to: thirdFileURL, atomically: true, encoding: .utf8)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL, thirdFileURL],
            origin: .manual,
            slotStrategy: .reuseEmptySlotForFirst
        ))

        #expect(harness.controller.documents.count == 3)
        let openFileNames = Set(harness.controller.documents.compactMap { $0.readerStore.fileURL?.lastPathComponent })
        #expect(openFileNames == ["alpha.md", "beta.md", "zeta.md"])
    }

    @Test @MainActor func openDeduplicatesAndSortsAlphabetically() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.secondaryFileURL, harness.primaryFileURL, harness.primaryFileURL],
            origin: .manual
        ))

        #expect(harness.controller.documents.count == 2)
        let orderedNames = harness.controller.documents.compactMap { $0.readerStore.fileURL?.lastPathComponent }
        #expect(orderedNames == ["alpha.md", "zeta.md"])
    }

    @Test @MainActor func openWithReplaceSelectedSlotReplacesContent() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL?.lastPathComponent == "alpha.md")
    }

    @Test @MainActor func openWithDeferThenMaterializeDefersAllFiles() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .folderWatchInitialBatchAutoOpen,
            materializationStrategy: .deferThenMaterializeNewest(count: 1)
        ))

        let deferredCount = harness.controller.documents.filter { $0.readerStore.isDeferredDocument }.count
        let loadedCount = harness.controller.documents.filter { !$0.readerStore.isDeferredDocument && $0.readerStore.fileURL != nil }.count

        #expect(deferredCount == 1)
        #expect(loadedCount == 1)
    }

    @Test @MainActor func openWithAlwaysAppendDoesNotReuseEmptySlot() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))

        #expect(harness.controller.documents.count == 2)
    }

    @Test @MainActor func openSkipsAlreadyOpenFiles() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL],
            origin: .manual,
            slotStrategy: .replaceSelectedSlot
        ))

        #expect(harness.controller.documents.count == 1)

        coordinator.open(FileOpenRequest(
            fileURLs: [harness.primaryFileURL, harness.secondaryFileURL],
            origin: .manual,
            slotStrategy: .alwaysAppend
        ))

        #expect(harness.controller.documents.count == 2)
        let openFileNames = Set(harness.controller.documents.compactMap { $0.readerStore.fileURL?.lastPathComponent })
        #expect(openFileNames == ["alpha.md", "zeta.md"])
    }

    @Test @MainActor func openEmptyURLListIsNoOp() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }
        let coordinator = FileOpenCoordinator(controller: harness.controller)

        coordinator.open(FileOpenRequest(
            fileURLs: [],
            origin: .manual
        ))

        #expect(harness.controller.documents.count == 1)
        #expect(harness.controller.selectedReaderStore.fileURL == nil)
    }
}
