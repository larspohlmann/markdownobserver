import Foundation
import Testing
@testable import minimark

@Suite
struct WindowFolderWatchOpenControllerTests {

    @Test @MainActor func enqueueAddsPendingEvent() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        let controller = WindowFolderWatchOpenController(
            fileOpenCoordinator: harness.controller.fileOpenCoordinator,
            isHostWindowAttached: { false },
            onAfterFlush: {}
        )

        controller.enqueue(
            FolderWatchChangeEvent(
                fileURL: URL(fileURLWithPath: "/tmp/event.md"),
                kind: .added
            ),
            folderWatchSession: nil,
            origin: .folderWatchAutoOpen
        )

        #expect(controller.hasPendingEvents)
    }

    @Test @MainActor func flushWithoutHostWindowKeepsPendingEvents() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        var afterFlushCallCount = 0
        let controller = WindowFolderWatchOpenController(
            fileOpenCoordinator: harness.controller.fileOpenCoordinator,
            isHostWindowAttached: { false },
            onAfterFlush: { afterFlushCallCount += 1 }
        )

        controller.enqueue(
            FolderWatchChangeEvent(
                fileURL: URL(fileURLWithPath: "/tmp/event.md"),
                kind: .modified,
                previousMarkdown: "# Before"
            ),
            folderWatchSession: nil,
            origin: .folderWatchAutoOpen
        )

        controller.flush()

        #expect(controller.hasPendingEvents)
        #expect(afterFlushCallCount == 0)
    }

    @Test @MainActor func flushWithHostWindowConsumesBatchAndInvokesAfterFlush() throws {
        let harness = try ReaderSidebarControllerTestHarness()
        defer { harness.cleanup() }

        var isAttached = false
        var afterFlushCallCount = 0
        let controller = WindowFolderWatchOpenController(
            fileOpenCoordinator: harness.controller.fileOpenCoordinator,
            isHostWindowAttached: { isAttached },
            onAfterFlush: { afterFlushCallCount += 1 }
        )

        let fileURL = harness.primaryFileURL
        controller.enqueue(
            FolderWatchChangeEvent(fileURL: fileURL, kind: .added),
            folderWatchSession: nil,
            origin: .folderWatchAutoOpen
        )
        #expect(controller.hasPendingEvents)

        isAttached = true
        controller.flush()

        #expect(!controller.hasPendingEvents)
        #expect(afterFlushCallCount == 1)
    }
}
