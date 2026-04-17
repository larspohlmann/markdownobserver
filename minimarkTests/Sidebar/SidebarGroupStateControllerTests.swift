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
            doc.documentStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
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

        let state = FavoriteWorkspaceState(
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

    @Test @MainActor func selectingAlgorithmicSortPreservesManualOrder() throws {
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

        #expect(controller.manualGroupOrder == [harness.directoryPath(for: "beta")])
        #expect(groups.first?.displayName == "alpha")
    }

    @Test @MainActor func switchingBackToManualOrderRestoresCustomOrder() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let gammaPath = harness.directoryPath(for: "gamma")
        let alphaPath = harness.directoryPath(for: "alpha")
        let betaPath = harness.directoryPath(for: "beta")
        controller.manualGroupOrder = [gammaPath, alphaPath, betaPath]
        controller.sortMode = .manualOrder

        controller.sortMode = .nameAscending

        controller.sortMode = .manualOrder

        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }

        #expect(groups.map(\.id) == [gammaPath, alphaPath, betaPath])
    }

    @Test @MainActor func manualOrderPreservesPinnedGroupFloat() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        for doc in harness.documents {
            doc.documentStore.testSetFileLastModifiedAt(Date(timeIntervalSince1970: 1000))
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

    // MARK: - Expand/Collapse All + Restore

    @Test @MainActor func expandAllThenRestoreRevertsState() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        let alphaPath = harness.directoryPath(for: "alpha")
        let betaPath = harness.directoryPath(for: "beta")
        controller.collapsedGroupIDs = [alphaPath, betaPath]

        controller.expandAllGroups()
        #expect(controller.collapsedGroupIDs.isEmpty)
        #expect(controller.isInBulkExpandState)

        controller.restoreManualExpandState()
        #expect(controller.collapsedGroupIDs == [alphaPath, betaPath])
        #expect(!controller.isInBulkExpandState)
    }

    @Test @MainActor func collapseAllThenRestoreRevertsState() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaPath = harness.directoryPath(for: "alpha")
        let betaPath = harness.directoryPath(for: "beta")
        let gammaPath = harness.directoryPath(for: "gamma")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)
        controller.collapsedGroupIDs = [gammaPath]

        controller.collapseAllGroups()
        #expect(controller.collapsedGroupIDs == [alphaPath, betaPath, gammaPath])
        #expect(controller.isInBulkExpandState)

        controller.restoreManualExpandState()
        #expect(controller.collapsedGroupIDs == [gammaPath])
        #expect(!controller.isInBulkExpandState)
    }

    @Test @MainActor func collapseAllThenReorderThenRestorePreservesCorrectGroups() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta", "gamma", "delta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let alphaPath = harness.directoryPath(for: "alpha")
        let betaPath = harness.directoryPath(for: "beta")
        let gammaPath = harness.directoryPath(for: "gamma")
        let deltaPath = harness.directoryPath(for: "delta")

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        // 1. Collapse all
        controller.collapsedGroupIDs = [alphaPath, betaPath, gammaPath, deltaPath]

        // 2. Expand alpha and beta manually
        controller.setGroupExpanded(alphaPath, isExpanded: true)
        controller.setGroupExpanded(betaPath, isExpanded: true)
        #expect(!controller.isInBulkExpandState)

        // 3. Collapse all via button
        controller.collapseAllGroups()
        #expect(controller.collapsedGroupIDs == [alphaPath, betaPath, gammaPath, deltaPath])
        #expect(controller.isInBulkExpandState)

        // 4. Reorder via drag (move first group to third position)
        guard case .grouped(let groups) = controller.computedGrouping else {
            Issue.record("Expected grouped result")
            return
        }
        let firstID = groups[0].id
        controller.moveGroup(from: 0, to: 2)

        // Verify reorder happened and snapshot survived
        #expect(controller.isInBulkExpandState)
        guard case .grouped(let reorderedGroups) = controller.computedGrouping else {
            Issue.record("Expected grouped result after reorder")
            return
        }
        #expect(reorderedGroups[0].id != firstID)

        // 5. Restore
        controller.restoreManualExpandState()

        // Alpha and beta should be expanded (not collapsed), gamma and delta collapsed
        #expect(!controller.collapsedGroupIDs.contains(alphaPath))
        #expect(!controller.collapsedGroupIDs.contains(betaPath))
        #expect(controller.collapsedGroupIDs.contains(gammaPath))
        #expect(controller.collapsedGroupIDs.contains(deltaPath))
        #expect(!controller.isInBulkExpandState)
    }

    @Test @MainActor func manualToggleClearsBulkExpandState() throws {
        let harness = try ReaderSidebarGroupingTestHarness(
            subdirectories: ["alpha", "beta"],
            filesPerSubdirectory: 1
        )
        defer { harness.cleanup() }

        let controller = SidebarGroupStateController()
        controller.updateDocuments(harness.documents)

        controller.expandAllGroups()
        #expect(controller.isInBulkExpandState)

        controller.setGroupExpanded(harness.directoryPath(for: "alpha"), isExpanded: false)
        #expect(!controller.isInBulkExpandState)
    }
}
