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
                indicatorState: .externalChange,
                indicatorPulseToken: 0
            ),
            testsDoc.id: SidebarRowState(
                id: testsDoc.id,
                title: "file0.md",
                lastModified: nil,
                sortDate: nil,
                isFileMissing: false,
                indicatorState: .none,
                indicatorPulseToken: 0
            )
        ]

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents, rowStates: rowStates)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.groupIndicatorStates[srcPath] == [.externalChange])
        #expect(controller.groupIndicatorPulseTokens[srcPath] == 1)
    }

    @Test @MainActor func groupIndicatorStatesIncludeAllPresentKinds() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src"],
            filesPerSubdirectory: 2
        )
        defer { harness.cleanup() }

        let srcDocs = harness.documentsInSubdirectory("src")
        let yellowDoc = try #require(srcDocs.first)
        let greenDoc = try #require(srcDocs.dropFirst().first)

        let rowStates: [UUID: SidebarRowState] = [
            yellowDoc.id: SidebarRowState(
                id: yellowDoc.id,
                title: "yellow.md",
                lastModified: nil,
                sortDate: nil,
                isFileMissing: false,
                indicatorState: .externalChange,
                indicatorPulseToken: 0
            ),
            greenDoc.id: SidebarRowState(
                id: greenDoc.id,
                title: "green.md",
                lastModified: nil,
                sortDate: nil,
                isFileMissing: false,
                indicatorState: .addedExternalChange,
                indicatorPulseToken: 0
            )
        ]

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents, rowStates: rowStates)

        let srcPath = harness.directoryPath(for: "src")
        #expect(controller.groupIndicatorStates[srcPath] == [.addedExternalChange, .externalChange])
        #expect(controller.groupIndicatorPulseTokens[srcPath] == 1)
    }

    @Test @MainActor func groupIndicatorPulseTokenIncrementsWhenIndicatorsChange() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["src"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let srcDoc = try #require(harness.documentsInSubdirectory("src").first)
        let srcPath = harness.directoryPath(for: "src")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(
            harness.documents,
            rowStates: [
                srcDoc.id: SidebarRowState(
                    id: srcDoc.id,
                    title: "file0.md",
                    lastModified: nil,
                    sortDate: nil,
                    isFileMissing: false,
                    indicatorState: .none,
                    indicatorPulseToken: 0
                )
            ]
        )

        let initialToken = controller.groupIndicatorPulseTokens[srcPath] ?? 0

        controller.updateDocuments(
            harness.documents,
            rowStates: [
                srcDoc.id: SidebarRowState(
                    id: srcDoc.id,
                    title: "file0.md",
                    lastModified: nil,
                    sortDate: nil,
                    isFileMissing: false,
                    indicatorState: .externalChange,
                    indicatorPulseToken: 1
                )
            ]
        )

        let updatedToken = controller.groupIndicatorPulseTokens[srcPath] ?? 0
        #expect(updatedToken == initialToken + 1)
    }

    @Test @MainActor func applyWorkspaceStateRestoresAllGroupState() throws {
        let controller = SidebarGroupStateController()

        let state = ReaderFavoriteWorkspaceState(
            fileSortMode: .nameAscending,
            groupSortMode: .nameDescending,
            sidebarPosition: .sidebarLeft,
            sidebarWidth: 300,
            pinnedGroupIDs: ["/path/a"],
            collapsedGroupIDs: ["/path/b"],
            manualGroupOrder: ["/path/x", "/path/y"]
        )

        controller.applyWorkspaceState(state)

        #expect(controller.sortMode == .nameDescending)
        #expect(controller.pinnedGroupIDs == ["/path/a"])
        #expect(controller.collapsedGroupIDs == ["/path/b"])
        #expect(controller.manualGroupOrder == ["/path/x", "/path/y"])
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

    @Test @MainActor func moveGroupSetsManualOrderAndSwitchesSortMode() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        controller.moveGroup(from: 2, to: 0)

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(controller.sortMode == .manualOrder)
        let gammaPath = harness.directoryPath(for: "gamma")
        #expect(groups.first?.id == gammaPath)
    }

    @Test @MainActor func manualOrderReordersGroupsAndAppendsNewOnes() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let gammaPath = harness.directoryPath(for: "gamma")
        let alphaPath = harness.directoryPath(for: "alpha")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.manualGroupOrder = [gammaPath, alphaPath]
        controller.sortMode = .manualOrder

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(groups.map(\.id) == [gammaPath, alphaPath, harness.directoryPath(for: "beta")])
    }

    @Test @MainActor func selectingAlgorithmicSortClearsManualOrder() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.manualGroupOrder = [harness.directoryPath(for: "beta")]
        controller.sortMode = .manualOrder

        controller.sortMode = .nameAscending

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(controller.manualGroupOrder == nil)
        #expect(groups.first?.displayName == "alpha")
    }

    @Test @MainActor func manualOrderPreservesPinnedGroupFloat() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        for doc in harness.documents {
            doc.readerStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
        }

        let betaPath = harness.directoryPath(for: "beta")
        let gammaPath = harness.directoryPath(for: "gamma")
        let alphaPath = harness.directoryPath(for: "alpha")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.pinnedGroupIDs = [betaPath]
        controller.manualGroupOrder = [gammaPath, alphaPath, betaPath]
        controller.sortMode = .manualOrder

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(groups[0].id == betaPath)
        #expect(groups[0].isPinned == true)
        #expect(groups[1].id == gammaPath)
        #expect(groups[2].id == alphaPath)
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
