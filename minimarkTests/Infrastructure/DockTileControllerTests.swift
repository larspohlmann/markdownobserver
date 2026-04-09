import Foundation
import Testing
@testable import minimark

@Suite(.serialized)
struct DockTileControllerTests {

    @Test @MainActor func emptyByDefault() {
        let controller = DockTileController()
        #expect(controller.createdCount == 0)
        #expect(controller.modifiedCount == 0)
        #expect(controller.deletedCount == 0)
    }

    @Test @MainActor func countsSingleWindowRowStates() {
        let controller = DockTileController()
        let windowToken = UUID()

        let docA = UUID()
        let docB = UUID()
        let docC = UUID()

        let rowStates: [UUID: SidebarRowState] = [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .addedExternalChange, indicatorPulseToken: 0
            ),
            docB: SidebarRowState(
                id: docB, title: "b.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
            docC: SidebarRowState(
                id: docC, title: "c.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .deletedExternalChange, indicatorPulseToken: 0
            ),
        ]

        controller.updateRowStates(for: windowToken, rowStates: rowStates)

        #expect(controller.createdCount == 1)
        #expect(controller.modifiedCount == 1)
        #expect(controller.deletedCount == 1)
    }

    @Test @MainActor func aggregatesAcrossMultipleWindows() {
        let controller = DockTileController()
        let window1 = UUID()
        let window2 = UUID()

        let docA = UUID()
        let docB = UUID()

        controller.updateRowStates(for: window1, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .addedExternalChange, indicatorPulseToken: 0
            ),
        ])

        controller.updateRowStates(for: window2, rowStates: [
            docB: SidebarRowState(
                id: docB, title: "b.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .addedExternalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.createdCount == 2)
        #expect(controller.modifiedCount == 0)
        #expect(controller.deletedCount == 0)
    }

    @Test @MainActor func removingWindowUpdatesCount() {
        let controller = DockTileController()
        let window1 = UUID()
        let window2 = UUID()

        let docA = UUID()
        let docB = UUID()

        controller.updateRowStates(for: window1, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
        ])
        controller.updateRowStates(for: window2, rowStates: [
            docB: SidebarRowState(
                id: docB, title: "b.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.modifiedCount == 2)

        controller.removeRowStates(for: window1)

        #expect(controller.modifiedCount == 1)
    }

    @Test @MainActor func ignoresNoneIndicatorState() {
        let controller = DockTileController()
        let windowToken = UUID()

        let docA = UUID()
        let docB = UUID()

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .none, indicatorPulseToken: 0
            ),
            docB: SidebarRowState(
                id: docB, title: "b.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.createdCount == 0)
        #expect(controller.modifiedCount == 1)
        #expect(controller.deletedCount == 0)
    }

    @Test @MainActor func updatingWindowReplacesOldStates() {
        let controller = DockTileController()
        let windowToken = UUID()

        let docA = UUID()

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .addedExternalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.createdCount == 1)

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .none, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.createdCount == 0)
    }

    @Test @MainActor func transitionFromAddedToModifiedUpdatesCount() {
        let controller = DockTileController()
        let windowToken = UUID()
        let docA = UUID()

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .addedExternalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(controller.createdCount == 1)
        #expect(controller.modifiedCount == 0)

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 1
            ),
        ])

        #expect(controller.createdCount == 0)
        #expect(controller.modifiedCount == 1)
    }

    @Test @MainActor func notifiesOnCountChange() {
        var updateCount = 0
        let controller = DockTileController()
        controller.onCountsChanged = { _, _, _ in
            updateCount += 1
        }

        let windowToken = UUID()
        let docA = UUID()

        controller.updateRowStates(for: windowToken, rowStates: [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
        ])

        #expect(updateCount == 1)
    }

    @Test @MainActor func doesNotNotifyWhenCountsUnchanged() {
        var updateCount = 0
        let controller = DockTileController()
        controller.onCountsChanged = { _, _, _ in
            updateCount += 1
        }

        let windowToken = UUID()
        let docA = UUID()

        let rowStates: [UUID: SidebarRowState] = [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 0
            ),
        ]

        controller.updateRowStates(for: windowToken, rowStates: rowStates)
        #expect(updateCount == 1)

        // Same counts, different pulse token — should not notify
        let rowStates2: [UUID: SidebarRowState] = [
            docA: SidebarRowState(
                id: docA, title: "a.md", lastModified: nil, sortDate: nil,
                isFileMissing: false, indicatorState: .externalChange, indicatorPulseToken: 1
            ),
        ]

        controller.updateRowStates(for: windowToken, rowStates: rowStates2)
        #expect(updateCount == 1)
    }
}
