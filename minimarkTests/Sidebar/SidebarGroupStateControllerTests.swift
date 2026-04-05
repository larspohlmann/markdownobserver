import Foundation
import Observation
import Testing
@testable import minimark

@Suite(.serialized)
struct SidebarGroupStateControllerTests {

    @Test @MainActor func recomputesGroupingWhenDocumentsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.count == 2)
    }

    @Test @MainActor func recomputesGroupingWhenSortModeChanges() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["zeta", "alpha"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        controller.sortMode = .nameAscending

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.first?.displayName == "alpha")
    }

    @Test @MainActor func recomputesGroupingWhenPinnedIDsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        for doc in harness.documents {
            doc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let betaPath = harness.directoryPath(for: "beta")
        controller.pinnedGroupIDs = [betaPath]

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        #expect(groups.first?.displayName == "beta")
        #expect(groups.first?.isPinned == true)
    }

    @Test @MainActor func collapsedIDsChangeDoesNotRecomputeGrouping() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        var groupingChanged = false
        withObservationTracking {
            _ = controller.computedGrouping
        } onChange: {
            groupingChanged = true
        }

        controller.collapsedGroupIDs.insert("src")

        #expect(!groupingChanged)
    }

    @Test @MainActor func groupIndicatorStatesReflectDocumentState() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src", "tests"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let srcDoc = harness.documentsInSubdirectory("src").first!
        let testsDoc = harness.documentsInSubdirectory("tests").first!

        let rowStates: [UUID: SidebarRowState] = [
            srcDoc.id: SidebarRowState(
                id: srcDoc.id,
                title: "file0.md",
                lastModified: nil,
                sortDate: nil,
                isFileMissing: false,
                indicatorState: .externalChange
            ),
            testsDoc.id: SidebarRowState(
                id: testsDoc.id,
                title: "file0.md",
                lastModified: nil,
                sortDate: nil,
                isFileMissing: false,
                indicatorState: .none
            )
        ]

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents, rowStates: rowStates)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.groupIndicatorStates[srcPath] == .externalChange)
    }

    @Test @MainActor func applyWorkspaceStateRestoresAllGroupState() throws {
        let controller = SidebarGroupStateController()

        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .nameDescending,
            sidebarPosition: .sidebarLeft,
            sidebarWidth: 300,
            pinnedGroupIDs: ["/path/a"],
            collapsedGroupIDs: ["/path/b"]
        )

        controller.applyWorkspaceState(state)

        #expect(controller.sortMode == .nameDescending)
        #expect(controller.pinnedGroupIDs == ["/path/a"])
        #expect(controller.collapsedGroupIDs == ["/path/b"])
    }

    @Test @MainActor func persistenceSnapshotCapturesCurrentState() throws {
        let controller = SidebarGroupStateController()
        controller.sortMode = .nameAscending
        controller.pinnedGroupIDs = ["/a"]
        controller.collapsedGroupIDs = ["/b"]

        let snapshot = controller.persistenceSnapshot
        #expect(snapshot.sortMode == .nameAscending)
        #expect(snapshot.pinnedGroupIDs == ["/a"])
        #expect(snapshot.collapsedGroupIDs == ["/b"])
    }

    @Test @MainActor func prunesStaleGroupIDsWhenDocumentsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.collapsedGroupIDs = ["/stale/path", harness.directoryPath(for: "src")]
        controller.pinnedGroupIDs = ["/stale/path", harness.directoryPath(for: "src")]

        controller.updateDocuments(harness.documents)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.collapsedGroupIDs == [srcPath])
        #expect(controller.pinnedGroupIDs == [srcPath])
    }
}
